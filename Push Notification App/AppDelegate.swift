//
//  AppDelegate.swift
//  Push Notification App
//
//  Created by Carlos Macasaet on 15/11/15.
//  Copyright © 2015 Carlos Macasaet. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    // view
    var window: UIWindow?

    // controller

    // MARK: delegate methods
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool
    {
        let readAction = UIMutableUserNotificationAction() // value type fail!
        readAction.identifier = "READ_ACTION"
        readAction.title = "Read"
        readAction.activationMode = .Foreground
        readAction.destructive = false
        readAction.authenticationRequired = true

        let ignoreAction = UIMutableUserNotificationAction()
        ignoreAction.identifier = "IGNORE_ACTION"
        ignoreAction.title = "Ignore"
        ignoreAction.activationMode = .Background
        ignoreAction.destructive = false
        ignoreAction.authenticationRequired = false

        let deleteAction = UIMutableUserNotificationAction()
        deleteAction.identifier = "DELETE_ACTION"
        deleteAction.title = "Delete"
        deleteAction.activationMode = .Foreground
        deleteAction.destructive = true
        deleteAction.authenticationRequired = true

        let category = UIMutableUserNotificationCategory()
        category.identifier = "MESSAGE_CATEGORY"
        category.setActions([ readAction, ignoreAction, deleteAction ], forContext: .Default )
        category.setActions( [ readAction, ignoreAction ], forContext: .Minimal )

        let notificationSettings = UIUserNotificationSettings( forTypes: [ .Alert, .Badge, .Sound ], categories: [ category ] )
        application.registerForRemoteNotifications()
        application.registerUserNotificationSettings(notificationSettings)

        if let options = launchOptions
        {
            createAlert( options.description )
        }

        return true
    }

    // MARK: Notification Delegates
    func application( application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: NSData ) {
        NSLog( "deviceToken: %@", deviceToken );
    }

    func application(application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: NSError) {
        NSLog( "unable to register for remote notifications: %@", error )
    }

    func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) {
        createAlert( userInfo.description )
    }

    func application(application: UIApplication, handleActionWithIdentifier identifier: String?, forRemoteNotification userInfo: [NSObject : AnyObject], completionHandler: () -> Void) {
        guard let identifier = identifier else
        {
            completionHandler()
            return
        }
        switch( identifier )
        {
            case "READ_ACTION":
                createAlert( "Read" )
                break;
            case "IGNORE_ACTION":
                break;
            case "DELETE_ACTION":
                createAlert( "Delete" )
                break;
            default:
                break;
        }
        completionHandler()
    }

    // MARK: Internal
    internal func createAlert( message:String )
    {
        let view = UIAlertView( title: "Push Notification", message: message, delegate: self, cancelButtonTitle: "Acknowledge")
        view.show()
    }

}

