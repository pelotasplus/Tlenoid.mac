//
//  Tlenoid.m
//  Tlenoid
//
//  Created by Aleksander Piotrowski on 29/10/13.
//  Copyright (c) 2013 pelotasplus Aleksander Piotrowski. All rights reserved.
//

#import "Tlenoid.h"

@implementation Tlenoid

// IMServicePlugIn

- (id)initWithServiceApplication:(id <IMServiceApplication>)serviceApplication {
    NSLog(@"initWithServiceApplication");

    if ((self = [super init])) {
        _application = serviceApplication;
        _tlenConnection = [[TlenConnection alloc] initWithDelegate:self];
    }

    return self;
}

- (oneway void)updateAccountSettings:(NSDictionary *)accountSettings {
    NSLog(@"updateAccountSettings: %@", accountSettings);
    _accountSettings = accountSettings;
    _username = [accountSettings objectForKey:IMAccountSettingLoginHandle];
    _password = [accountSettings objectForKey:IMAccountSettingPassword];
}

- (oneway void)login {
    NSLog(@"login begin");

//    [_tlenConnection initStream:@"s1._tlenConnection.pl" port:443];
    [_tlenConnection login:_username password:_password];

    NSLog(@"login end");
}

- (oneway void)logout {
    NSLog(@"logout");

    [_tlenConnection logout];
//    [_tlenConnection destroy];

    NSLog(@"logout end");
}

- (oneway void)updateSessionProperties:(NSDictionary *)properties {
    NSLog(@"updateSessionProperties: properties=%@", properties);
}

- (oneway void) requestGroupList {
    NSLog(@"requestGroupList");

    NSMutableDictionary *grp = [NSMutableDictionary dictionary];
    [grp setObject:@"Campfire" forKey:IMGroupListNameKey];
    NSArray *handles = [NSArray alloc];
    [grp setObject:handles forKey:IMGroupListHandlesKey];

    NSDictionary *group = grp;
    [_application plugInDidUpdateGroupList:[NSArray arrayWithObject:group] error:nil];

    [_tlenConnection requestGroupList];
    // No real buddy list support, just send back the list containing the console user
//    [self _sendBuddyList];
}

// TlenConnectionDelegate

- (void)connection:(TlenConnection *)connection loggedIn:(BOOL)success {
    if (success) {
        [_application plugInDidLogIn];
    } else {
        [_application plugInDidFailToAuthenticate];
    }
}

- (void)connection:(TlenConnection *)connection loggedOut:(BOOL)success {
    // pass
}

- (oneway void)userDidStartTypingToHandle:(NSString *)handle {

}

- (oneway void)userDidStopTypingToHandle:(NSString *)handle {

}

- (oneway void)sendMessage:(IMServicePlugInMessage *)message toHandle:(NSString *)handle {

}

@end
