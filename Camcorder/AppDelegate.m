//
//  AppDelegate.m
//  Camcorder
//
//  Created by Brian Lambert on 4/6/12.
//  Copyright (c) 2012 iq320.com. All rights reserved.
//

#import "AppDelegate.h"
#import "MainViewController.h"

// AppDelegate (UIApplicationDelegate) class.
@interface AppDelegate (UIApplicationDelegate) <UIApplicationDelegate>
@end

// AppDelegate class.
@implementation AppDelegate
{
@private
    UIWindow * window;
    MainViewController * mainViewController_;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Allocate and initialize the window and main view controller.
    window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    mainViewController_ = [[MainViewController alloc] init];

    // Start the application.
    [window setRootViewController:mainViewController_];
    [window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
}

- (void)applicationWillTerminate:(UIApplication *)application
{
}

@end
