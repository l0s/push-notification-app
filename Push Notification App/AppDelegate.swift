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

    // MARK: services
    var sns:AWSSNS!
    lazy var serviceManager = AWSServiceManager.defaultServiceManager()
    lazy var bundle = NSBundle.mainBundle()

    // MARK: properties
    /// private settings
    var settings:Dictionary<String, AnyObject>!
    var pushNotificationsEnabled = false
    /// the APNS device token iff the user opted-in to notifications
    var deviceToken:String! // set by application didRegisterForRemoteNotificationsWithDeviceToken
    /// The endpoint is specific to this device and the application in AWS SNS
    var endpointArn:String?

    var userNotificationCategories:Set<UIUserNotificationCategory> = {
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

        return [ category ]
    }()

    // MARK: delegate methods
    func application( application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]? ) -> Bool
    {
        /* AWS Configuration */
        settings =
            NSDictionary( contentsOfFile: self.bundle.pathForResource( "private", ofType: "plist" )! ) as! Dictionary<String, AnyObject>
        let regionType = AWSRegionType( rawValue: settings[ "aws_region" ] as! Int )!
        let identityPoolId = settings[ "aws_identity_pool_id" ] as! String

        // configure Cognito
        let credentialsProvider =
            AWSCognitoCredentialsProvider( regionType: regionType, identityPoolId: identityPoolId )
        let serviceConfiguration =
            AWSServiceConfiguration( region: regionType, credentialsProvider: credentialsProvider )
        serviceManager.defaultServiceConfiguration = serviceConfiguration

        // configure SNS
        AWSSNS.registerSNSWithConfiguration( serviceConfiguration, forKey: "SNS" )
        sns = AWSSNS( forKey: "SNS" )

        registerForNotifications( application )

        if let options = launchOptions
        {
            createAlert( options.description )
        }

        return true
    }

    internal func registerForNotifications( application: UIApplication )
    {
        let notificationSettings =
            UIUserNotificationSettings( forTypes: [ .Alert, .Badge, .Sound ],
                                      categories: userNotificationCategories )
        application.registerForRemoteNotifications()
        application.registerUserNotificationSettings( notificationSettings )
    }

    // MARK: Notification Delegates
    func application( application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: NSData )
    {
        NSLog( "deviceToken: %@", deviceToken );
        self.deviceToken =
            deviceToken.description.stringByTrimmingCharactersInSet( NSCharacterSet(charactersInString: "<>") ).stringByReplacingOccurrencesOfString(" ", withString: "")

        var taskChain = AWSTask( result: nil )
        if( endpointArn == nil )
        {
            NSLog( "endpoint not yet set, scheduling registration with application" )
            // register this session as an endpoint to the application
            taskChain = taskChain.continueWithSuccessBlock()
            {
                task in

                let request = AWSSNSCreatePlatformEndpointInput()
                request.token = self.deviceToken
                request.platformApplicationArn = self.settings[ "aws_sns_sandbox_arn" ] as! String

                NSLog( "registering endpoint with application" )
                // duplicated code, 1st time
                return self.sns.createPlatformEndpoint( request ).continueWithSuccessBlock()
                {
                    task in
                    NSLog( "registration successful, setting endpointArn" )
                    let result = task.result as! AWSSNSCreateEndpointResponse
                    self.endpointArn = result.endpointArn
                    NSLog( "endpointArn: " + self.endpointArn! )
                    return task
                }
            }
        }
        taskChain.continueWithSuccessBlock()
        {
            task in
            NSLog( "Getting endpoint attributes for: \(self.endpointArn)" )
            let request = AWSSNSGetEndpointAttributesInput()
            request.endpointArn = self.endpointArn
            return self.sns.getEndpointAttributes( request )
        }.continueWithBlock()
        {
            task in
            if let error = task.error
            {
                NSLog( "Error getting endpoint attributes: \(error.description)" )
                if error.domain == AWSSNSErrorDomain && AWSSNSErrorType( rawValue: error.code ) == .NotFound
                {
                    NSLog( "Endpoint was deleted, need to re-register" )
                    // endpoint was deleted, need to re-register
                    let request = AWSSNSCreatePlatformEndpointInput()
                    request.token = self.deviceToken
                    request.platformApplicationArn = self.settings[ "aws_sns_sandbox_arn" ] as! String

                    // duplicated code, 2nd time
                    return self.sns.createPlatformEndpoint( request ).continueWithSuccessBlock()
                    {
                        task in
                        let result = task.result as! AWSSNSCreateEndpointResponse
                        self.endpointArn = result.endpointArn
                        NSLog( "endpointArn: " + self.endpointArn! )
                        return task
                    }
                }
            }
            else if let result = task.result
            {
                let response = result as! AWSSNSGetEndpointAttributesResponse
                if (response.attributes[ "Token" ] as! String) != self.deviceToken || response.attributes[ "Enabled" ] as! String == "false"
                {
                    NSLog( "Endpoint registration out of date, updating" )
                    let updateRequest = AWSSNSSetEndpointAttributesInput()
                    updateRequest.endpointArn = self.endpointArn!
                    updateRequest.attributes = response.attributes // ooh, copy on write
                    updateRequest.attributes[ "Token" ] = self.deviceToken
                    updateRequest.attributes[ "Enabled" ] = "true"
                    return self.sns.setEndpointAttributes( updateRequest )
                }
            }
            return task
        }.continueWithBlock()
        {
            task in
            if let error = task.error
            {
                NSLog( "Error registering for push notifications: \(error.description)" )
                self.createAlert( "Error: \(error.description)" )
            }
            else if let exception = task.exception
            {
                NSLog( "Exception registering for push notifications: \(exception.description)" )
                self.createAlert( "Exception: \(exception.description)" )
            }
            else
            {
                NSLog( "Registered for push notifications!" )
                self.pushNotificationsEnabled = true
            }
            return task
        }
    }

    func application(application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: NSError) {
        NSLog( "unable to register for remote notifications: %@", error )
        pushNotificationsEnabled = false
    }

    func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) {
        NSLog( "Received notification: \(userInfo.description)" )
        createAlert( userInfo.description )
    }

    func application(application: UIApplication, handleActionWithIdentifier identifier: String?, forRemoteNotification userInfo: [NSObject : AnyObject], completionHandler: () -> Void) {
        NSLog( "Handling notification action: \(identifier)" )
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