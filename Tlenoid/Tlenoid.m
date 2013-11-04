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

- (id)initWithServiceApplication:(id <IMServiceApplication, IMServiceApplicationGroupListSupport>)serviceApplication {
    NSLog(@"initWithServiceApplication");

    if ((self = [super init])) {
        _application = serviceApplication;
        _tlenConnection = [[TlenConnection alloc] initWithDelegate:self];
        _users = [[NSMutableArray alloc] init];
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

// IMServicePlugInPresenceSupport

- (oneway void)updateSessionProperties:(NSDictionary *)properties {
    NSLog(@"updateSessionProperties: properties=%@", properties);

    [_tlenConnection updateSessionProperties:properties];
}

// IMServicePlugInGroupListSupport

- (oneway void) requestGroupList {
    NSLog(@"requestGroupList");

    [_tlenConnection requestGroupList];
}

// IMServicePlugInInstantMessagingSupport

- (oneway void)userDidStartTypingToHandle:(NSString *)handle {

}

- (oneway void)userDidStopTypingToHandle:(NSString *)handle {

}

- (oneway void)sendMessage:(IMServicePlugInMessage *)message toHandle:(NSString *)handle {

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

- (void)connection:(TlenConnection *)connection gotRoster:(NSArray *)users {
    NSLog(@"gotRoster %@", users);
    _users = [[NSMutableArray alloc] initWithArray:users];

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // IMGroupListHandlesKey
    [dict setObject:@"Tlenoid" forKey:IMGroupListNameKey];

    // IMGroupListHandlesKey
    NSMutableArray *handles = [[NSMutableArray alloc] init];
    for (NSDictionary *user in _users) {
        [handles addObject:[user objectForKey:@"jid"]];
    }
    [dict setObject:handles forKey:IMGroupListHandlesKey];

    NSLog(@"dict %@", dict);

    [_application plugInDidUpdateGroupList:[NSArray arrayWithObject:dict] error:nil];
}

@end
