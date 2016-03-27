//
//  AppDelegate.swift
//  Clipy
//
//  Created by 古林俊佑 on 2015/06/21.
//  Copyright (c) 2015年 Shunsuke Furubayashi. All rights reserved.
//

import Cocoa
import Sparkle
import Fabric
import Crashlytics
import RxCocoa
import RxSwift
import RxOptional
import NSObject_Rx

@NSApplicationMain
class AppDelegate: NSObject {

    // MARK: - Properties
    let snippetEditorController = CPYSnippetEditorWindowController(windowNibName: "CPYSnippetEditorWindowController")
    let defaults = NSUserDefaults.standardUserDefaults()
    
    // MARK: - Init
    override func awakeFromNib() {
        super.awakeFromNib()
        // Migrate Realm
        CPYUtilities.migrationRealm()
    }

    // MARK: - Override Methods
    override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
        if menuItem.action == Selector("clearAllHistory") {
            if CPYClip.allObjects().count == 0 {
                return false
            }
        }
        return true
    }
    
    // MARK: - Class Methods
    static func storeTypesDictinary() -> [String: NSNumber] {
        let storeTypes = CPYClipData.availableTypesString.reduce([String: NSNumber]()) { (var dict, type) in
            dict[type] = NSNumber(bool: true)
            return dict
        }
        return storeTypes
    }

    // MARK: - Menu Actions
    func showPreferenceWindow() {
        NSApp.activateIgnoringOtherApps(true)
        CPYPreferenceWindowController.sharedPrefsWindowController().showWindow(self)
    }
    
    func showSnippetEditorWindow() {
        NSApp.activateIgnoringOtherApps(true)
        snippetEditorController.showWindow(self)
    }
    
    func clearAllHistory() {
        let isShowAlert = defaults.boolForKey(kCPYPrefShowAlertBeforeClearHistoryKey)
        if isShowAlert {
            let alert = NSAlert()
            alert.messageText = LocalizedString.ClearHistory.value
            alert.informativeText = LocalizedString.ConfirmClearHistory.value
            alert.addButtonWithTitle(LocalizedString.ClearHistory.value)
            alert.addButtonWithTitle(LocalizedString.Cancel.value)
            alert.showsSuppressionButton = true
            
            NSApp.activateIgnoringOtherApps(true)
        
            let result = alert.runModal()
            if result != NSAlertFirstButtonReturn { return }
            
            if alert.suppressionButton?.state == NSOnState {
                defaults.setBool(false, forKey: kCPYPrefShowAlertBeforeClearHistoryKey)
            }
            defaults.synchronize()
        }
        
        ClipManager.sharedManager.clearAll()
    }
    
    func selectClipMenuItem(sender: NSMenuItem) {
        Answers.logCustomEventWithName("selectClipMenuItem", customAttributes: nil)
        if let primaryKey = sender.representedObject as? String, let clip = CPYClip(forPrimaryKey: primaryKey) {
            PasteboardManager.sharedManager.copyClipToPasteboard(clip)
            CPYUtilities.paste()
        } else {
            Answers.logCustomEventWithName("Cann't fetch clip data", customAttributes: nil)
            NSBeep()
        }
    }
    
    func selectSnippetMenuItem(sender: AnyObject) {
        Answers.logCustomEventWithName("selectSnippetMenuItem", customAttributes: nil)
        if let primaryKey = sender.representedObject as? String, let snippet = CPYSnippet(forPrimaryKey: primaryKey) {
            PasteboardManager.sharedManager.copyStringToPasteboard(snippet.content)
            CPYUtilities.paste()
        } else {
            Answers.logCustomEventWithName("Cann't fetch snippet data", customAttributes: nil)
            NSBeep()
        }
    }
    
    // MARK: - Login Item Methods
    private func promptToAddLoginItems() {
        let alert = NSAlert()
        alert.messageText = LocalizedString.LaunchClipy.value
        alert.informativeText = LocalizedString.LaunchSettingInfo.value
        alert.addButtonWithTitle(LocalizedString.LaunchOnStartup.value)
        alert.addButtonWithTitle(LocalizedString.DontLaunch.value)
        alert.showsSuppressionButton = true
        NSApp.activateIgnoringOtherApps(true)

        // 起動する選択時
        if alert.runModal() == NSAlertFirstButtonReturn {
            defaults.setBool(true, forKey: kCPYPrefLoginItemKey)
            toggleLoginItemState()
        }
        // Do not show this message again
        if alert.suppressionButton?.state == NSOnState {
            defaults.setBool(true, forKey: kCPYPrefSuppressAlertForLoginItemKey)
        }
        defaults.synchronize()
    }
    
    private func toggleAddingToLoginItems(enable: Bool) {
        let appPath = NSBundle.mainBundle().bundlePath
        if enable {
            NMLoginItems.removePathFromLoginItems(appPath)
            NMLoginItems.addPathToLoginItems(appPath, hide: false)
        } else {
            NMLoginItems.removePathFromLoginItems(appPath)
        }
    }
    
    private func toggleLoginItemState() {
        let isInLoginItems = NSUserDefaults.standardUserDefaults().boolForKey(kCPYPrefLoginItemKey)
        toggleAddingToLoginItems(isInLoginItems)
    }
    
    // MARK: - Version Up Methods
    private func checkUpdates() {
        let feed = "https://clipy-app.com/appcast.xml"
        if let feedURL = NSURL(string: feed) {
            SUUpdater.sharedUpdater().feedURL = feedURL
        }
    }

}

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // SDKs
        CPYUtilities.initSDKs()
        
        // UserDefaults
        CPYUtilities.registerUserDefaultKeys()
        
        // Regist Hotkeys
        CPYHotKeyManager.sharedManager.registerHotKeys()
        
        // Show Login Item
        if !defaults.boolForKey(kCPYPrefLoginItemKey) && !defaults.boolForKey(kCPYPrefSuppressAlertForLoginItemKey) {
            promptToAddLoginItems()
        }
        
        // Sparkle
        let updater = SUUpdater.sharedUpdater()
        checkUpdates()
        updater.automaticallyChecksForUpdates = defaults.boolForKey(kCPYEnableAutomaticCheckKey)
        updater.updateCheckInterval = NSTimeInterval(defaults.integerForKey(kCPYUpdateCheckIntervalKey))
    
        // Binding Events
        bind()
        
        // Managers
        MenuManager.sharedManager.setup()
        ClipManager.sharedManager.setup()
        HistoryManager.sharedManager.setup()
    }
    
    func applicationWillTerminate(aNotification: NSNotification) {
        CPYHotKeyManager.sharedManager.unRegisterHotKeys()
    }
}

// MARK: - Bind
private extension AppDelegate {
    private func bind() {
        // Login Item
        defaults.rx_observe(Bool.self, kCPYPrefLoginItemKey, options: [.New])
            .filterNil()
            .subscribeNext { [weak self] enabled in
                self?.toggleLoginItemState()
            }.addDisposableTo(rx_disposeBag)
        // Sleep Notification
        NSWorkspace.sharedWorkspace().notificationCenter.rx_notification(NSWorkspaceWillSleepNotification)
            .subscribeNext { notification in
                ClipManager.sharedManager.stopTimer()
            }.addDisposableTo(rx_disposeBag)
        NSWorkspace.sharedWorkspace().notificationCenter.rx_notification(NSWorkspaceDidWakeNotification)
            .subscribeNext { notification in
                ClipManager.sharedManager.startTimer()
            }.addDisposableTo(rx_disposeBag)
    }
}
