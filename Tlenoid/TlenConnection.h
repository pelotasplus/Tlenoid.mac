//
// Created by Aleksander Piotrowski on 03/11/13.
// Copyright (c) 2013 pelotasplus Aleksander Piotrowski. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TlenConnectionDelegate;

@interface TlenConnection : NSObject<NSStreamDelegate, NSXMLParserDelegate> {
    id<TlenConnectionDelegate> _delegate;

    NSInputStream *inputStream;
    NSOutputStream *outputStream;
    NSXMLParser *xmlParser;
    NSTimer *pingTimer;

    NSString *sessionId, *username, *password;
    NSXMLElement *currentElement, *root;

    // set our presence not before receiving roster
    BOOL gotRoster;
    NSDictionary *sessionProperties;
}

- (id) initWithDelegate:(id<TlenConnectionDelegate>)delegate;
- (void) setDelegate:(id<TlenConnectionDelegate>)delegate;
- (void)initStream:(NSString *)hostname port:(UInt32)port;
- (void)write:(NSString *)data;
- (void)login:(NSString *)username password:(NSString *)password;
- (void)logout;
//- (void)destroy;

- (void)requestGroupList;

- (void)updateSessionProperties:(NSDictionary *)dictionary;
@end

@protocol TlenConnectionDelegate
- (void)connection:(TlenConnection *)connection loggedIn:(BOOL)success;
- (void)connection:(TlenConnection *)connection loggedOut:(BOOL)success;
- (void)connection:(TlenConnection *)connection gotRoster:(NSArray *)users;
- (void)connection:(TlenConnection *)connection gotPresence:(NSDictionary *)presence;
- (void)connection:(TlenConnection *)connection parseError:(NSError *)error;
@end
