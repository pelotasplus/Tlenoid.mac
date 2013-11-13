//
//  Tlenoid.h
//  Tlenoid
//
//  Created by Aleksander Piotrowski on 29/10/13.
//  Copyright (c) 2013 pelotasplus Aleksander Piotrowski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IMServicePlugIn/IMServicePlugIn.h>

#import "TlenConnection.h"

@interface Tlenoid : NSObject<
    IMServicePlugIn,
    IMServicePlugInGroupListSupport,
    IMServicePlugInGroupListHandlePictureSupport,
    IMServicePlugInPresenceSupport,
    IMServicePlugInInstantMessagingSupport,
    TlenConnectionDelegate>
{
    id <
        IMServiceApplication,
        IMServiceApplicationGroupListSupport,
        IMServiceApplicationInstantMessagingSupport
    > _application;

    NSDictionary *_accountSettings;
    NSString *_username, *_password;
    TlenConnection *_tlenConnection;
    NSMutableArray *_users;
}

@end