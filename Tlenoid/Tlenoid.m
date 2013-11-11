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

#pragma mark -
#pragma mark IMServicePlugIn

- (id)initWithServiceApplication:(id <
    IMServiceApplication,
    IMServiceApplicationGroupListSupport,
//    IMServiceApplicationChatRoomSupport,
    IMServiceApplicationInstantMessagingSupport>)serviceApplication {

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
    [_tlenConnection login:_username password:_password];
}

- (oneway void)logout {
    [_tlenConnection logout];
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

#pragma mark -
#pragma mark IMServicePlugInInstantMessagingSupport

- (oneway void)userDidStartTypingToHandle:(NSString *)handle {
    NSLog(@"userDidStartTypingToHandle: handle=%@", handle);
    [_tlenConnection startedTyping:handle];
}

- (oneway void)userDidStopTypingToHandle:(NSString *)handle {
    NSLog(@"userDidStopTypingToHandle: handle=%@", handle);
    [_tlenConnection stopedTyping:handle];
}

- (oneway void)sendMessage:(IMServicePlugInMessage *)message toHandle:(NSString *)handle {
    NSLog(@"sendMessage");
    [_tlenConnection sendMessage:message toHandle:handle];
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
    _users = [[NSMutableArray alloc] initWithArray:users];

    // permissions
    NSNumber *permissions = [[NSNumber alloc] initWithInt:IMGroupListCanReorderGroup];

    // handles
    NSMutableArray *handles = [[NSMutableArray alloc] init];
    for (NSDictionary *user in _users) {
        [handles addObject:[user objectForKey:@"jid"]];
    }

    NSDictionary *defaultGroup = [[NSDictionary alloc] initWithObjectsAndKeys:
        IMGroupListDefaultGroup, IMGroupListNameKey,
        handles, IMGroupListHandlesKey,
        permissions, IMGroupListPermissionsKey,
        nil];

    NSArray *groups = [[NSArray alloc] initWithObjects:defaultGroup, nil];

    [_application plugInDidUpdateGroupList:groups error:nil];

    for (NSDictionary *user in _users) {
        [_application plugInDidUpdateProperties:user ofHandle:[user objectForKey:@"jid"]];
    }
}

- (void)connection:(TlenConnection *)connection gotPresence:(NSDictionary *)presence {
    NSString *jid = [presence valueForKey:@"jid"];
    NSLog(@"got presence: jid %@ presence %@", jid, presence);
    [_application plugInDidUpdateProperties:presence ofHandle:jid];
}

- (void)connection:(TlenConnection *)connection parseError:(NSError *)error {
    [_application plugInDidLogOutWithError:error reconnect:TRUE];
}

- (void)connection:(TlenConnection *)connection gotMessage:(NSString *)message from:(NSString *)from {
    IMServicePlugInMessage *m = [[IMServicePlugInMessage alloc] initWithContent:[[NSAttributedString alloc] initWithString:message]];
    [_application plugInDidReceiveMessage:m fromHandle:from];
}

- (void)connection:(TlenConnection *)connection messageSent:(IMServicePlugInMessage *)message from:(NSString *)jid {
    [_application plugInDidSendMessage:message toHandle:jid error:nil];
}

- (void)connection:(TlenConnection *)connection gotTyping:(NSString *)jid startedTyping:(BOOL)started {
    NSLog(@"gotTyping: jid=%@ started=%d", jid, started);

    if (started) {
        [_application handleDidStartTyping:jid];
    } else {
        [_application handleDidStopTyping:jid];
    }
}

@end
