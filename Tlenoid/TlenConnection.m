//
// Created by Aleksander Piotrowski on 03/11/13.
// Copyright (c) 2013 pelotasplus Aleksander Piotrowski. All rights reserved.
//

#import <Foundation/NSXMLElement.h>
#import <IMServicePlugIn/IMServicePlugIn.h>

#import "TlenConnection.h"
#import "auth.h"

@implementation TlenConnection
- (id) initWithDelegate:(id<TlenConnectionDelegate>)delegate {
    if ((self = [super init])) {
        [self setDelegate:delegate];
        gotRoster = FALSE;
    }

    return self;
}

- (NSString *) urldecode:(NSString *)encoded {
    NSString *decoded = [[encoded
            stringByReplacingOccurrencesOfString:@"+" withString:@" "]
            stringByReplacingPercentEscapesUsingEncoding:NSISOLatin2StringEncoding];
    return decoded;
}

- (NSString *) urlencode:(NSString *)string {
    NSString *encoded = [[string
            stringByReplacingOccurrencesOfString:@" " withString:@"+"]
            stringByAddingPercentEscapesUsingEncoding:NSISOLatin2StringEncoding];
    return encoded;
}

- (void) setDelegate:(id<TlenConnectionDelegate>)delegate
{
    _delegate = delegate;
}

- (void)initStream:(NSString *)hostname port:(UInt32)port {
    NSLog(@"initStream: hostname %@ port %u", hostname, port);

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStringRef cfHostname = (__bridge CFStringRef) hostname;
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, cfHostname, port, &readStream, &writeStream);
    inputStream = (__bridge NSInputStream *) readStream;
    outputStream = (__bridge NSOutputStream *) writeStream;
    outputStream.delegate = self;
    [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [inputStream open];
    [outputStream open];

    NSLog(@"inputStream %@ outputStream %@", inputStream, outputStream);

    xmlParser = [[NSXMLParser alloc] initWithStream:inputStream];
    [xmlParser setDelegate:self];
    dispatch_block_t dispatch_block = ^(void) {
        [xmlParser parse];
    };
    dispatch_queue_t dispatch_queue = dispatch_queue_create("parser.queue", NULL);
    dispatch_async(dispatch_queue, dispatch_block);
//    dispatch_release(dispatch_queue);

    NSLog(@"initStream end");
}

- (void)write:(NSString *)data {
    unsigned long len = data.length;
    const char *c = [data UTF8String];

    NSInteger r = [outputStream write:(uint8_t const *) c maxLength:len];
    NSLog(@"write: %s (length %lu) -> %ld", c, len, r);

    if (r != len) {
        [_delegate connection:self parseError:[outputStream streamError]];
    }
}

- (void)login:(NSString *)_username password:(NSString *)_password {
    username = _username;
    password = _password;

    [self initStream:@"s1.tlen.pl" port:443];

    NSString *s = @"<s v='7'>\n";
    [self write:s];

    [self startPingTimer];

}

- (void)startPingTimer {
    if (pingTimer != NULL) {
        [self stopPingTimer];
    }
    pingTimer = [NSTimer scheduledTimerWithTimeInterval:(6.0)
                                                 target:self
                                               selector:@selector(pingTimerFired:)
                                               userInfo:nil
                                                repeats:YES];

}

- (void)pingTimerFired:(id)pingTimerFired {
    NSLog(@"pingTimerFired");
    NSString *s = @"  \t  ";
    [self write:s];
}

- (void)stopPingTimer {
    if (pingTimer != NULL) {
        [pingTimer invalidate];
        pingTimer = nil;
    }
}

- (void)parser:(NSXMLParser *)parser
        didStartElement:(NSString *)elementName
        namespaceURI:(NSString *)namespaceURI
        qualifiedName:(NSString *)qName
        attributes:(NSDictionary *)attributeDict {
//    NSLog(@"didStartElement: %@, attributeDict: %@", elementName, attributeDict);

    NSXMLElement *element = [[NSXMLElement alloc] initWithName:elementName];
    for(id key in attributeDict) {
        NSString *value = [attributeDict objectForKey:key];
        NSXMLNode *xmlNode = [NSXMLNode attributeWithName:key stringValue:value];
        [element addAttribute:xmlNode];
    }

    // <s c="1" i="XYZ">
    if ([elementName isEqualToString:@"s"]) {
        sessionId = [attributeDict objectForKey:@"i"];
        char *hash = tlen_hash([password UTF8String], [sessionId UTF8String]);

        NSString *s = [NSString
                stringWithFormat:@"<iq type='set' id='%s'><query xmlns='jabber:iq:auth'><username>%s</username><host>tlen.pl</host><digest>%s</digest><resource>t</resource></query></iq>\n",
                [sessionId UTF8String],
                [username UTF8String],
                hash];
        [self write:s];
    } else {
        if (root == NULL) {
            root = element;
            currentElement= element;
        } else {
            [currentElement addChild:element];
            currentElement = element;
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
//    NSLog(@"foundCharacters: %@", string);

//    assert(currentElement != NULL);

    if (currentElement != NULL) {
        NSXMLNode *xmlNode = [NSXMLNode textWithStringValue:string];
        [currentElement addChild:xmlNode];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
//    NSLog(@"didEndElement: %@", elementName);

    // special case, ending <s> tag
    if ([elementName isEqualToString:@"s"] && currentElement == NULL) {
        [_delegate connection:self loggedOut:TRUE];
        return;
    }

    assert(currentElement != NULL);

    if ([root.name isEqualToString:elementName]) {
        [self processResponse];
        root = NULL;
        currentElement = NULL;
    } else if ([currentElement.name isEqualToString:elementName]) {
        currentElement = (NSXMLElement *) [currentElement parent];
    }
}

- (void)processResponse {
    NSLog(@"processResponse: root=%@", root);

    assert(root != NULL);

    NSString *s = root.name;

    if ([s isEqualToString:@"iq"]) {
        [self processIq];
    } else if ([s isEqualToString:@"presence"]) {
        [self processPresence];
    } else if ([s isEqualToString:@"message"]) {
        [self processMessage];
    } else if ([s isEqualToString:@"m"]) {
        [self processM];
    } else {
        NSLog(@"unknown XML %@", s);
    }
}

- (void)processM {
    NSLog(@"processM: root=%@", root);

    NSXMLNode *f, *tp;

    f = [root attributeForName:@"f"];
    tp = [root attributeForName:@"tp"];

    NSLog(@"processM f=%@ tp=%@", f, tp);

    if (! f || ! tp) {
        return;
    }

    NSLog(@"processM f=%@ tp=%@", [f objectValue], [tp stringValue]);

    NSLog(@"processM %d", [[tp objectValue] isEqualToString:@"t"]);
    NSLog(@"processM %d", [[tp stringValue] isEqualTo:@"t"]);

    BOOL startedTyping;

    if ([[tp objectValue] isEqualToString:@"t"]) {
        startedTyping = TRUE;
    } else if ([[tp objectValue] isEqualToString:@"u"]) {
        startedTyping = FALSE;
    } else {
        NSLog(@"unknown tp");
        return;
    }

    NSString *jid = [f stringValue];
    jid = [self stripHandle:jid];

    [_delegate connection:self gotTyping:jid startedTyping:startedTyping];
}

- (NSString*)stripHandle:(NSString *)handle {
    NSRange slash = [handle rangeOfString:@"/"];
    if (slash.location != NSNotFound) {
        return [handle substringToIndex:slash.location];
    } else {
        return handle;
    }
}

- (void)processMessage {
    NSXMLNode *jid = [root attributeForName:@"from"];

    NSString *body;
    for (NSXMLNode *child in [root children]) {
        if ([[child name] isEqualToString:@"body"]) {
            body = [child objectValue];
            body = [self urldecode:body];
            break;
        }
    }

    if (jid && body) {
        NSString *handle = [self stripHandle:[jid stringValue]];
        [_delegate connection:self gotMessage:body from:handle];
    }
}

- (void)processPresence {
    assert([root.name isEqualToString:@"presence"]);

    NSString *status = @"", *show = @"unavailable";

    NSXMLNode *from = [[root attributeForName:@"from"] objectValue];
    NSXMLNode *type = [[root attributeForName:@"type"] objectValue];

    NSLog(@"type from %@ %@", from, type);

    if (type != NULL) {
        show = (id) type;
    }

    NSLog(@"type2 from %@ %@", from, type);

    for (NSXMLNode *child in [root children]) {
        NSLog(@"processing child from %@ %@", from, child);
        if ([child.name isEqualToString:@"show"]) {
            show = [child objectValue];
        } else if ([child.name isEqualToString:@"status"]) {
            NSLog(@"status pre %@ %@", from, [child objectValue]);
            status = [self urldecode:[child objectValue]];
            NSLog(@"status after %@ %@", from, status);
//            status = [child objectValue];
        }
    }

    NSLog(@"show %@", show);

    if (status == NULL) status = @"";
    if (show == NULL) show = @"unavailable";

    NSLog(@"processPresence: from=%@ status=%@ show=%@", from, status, show);

    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];

    // IMHandlePropertyStatusMessage
    [dictionary setObject:status forKey:IMHandlePropertyStatusMessage];


    // IMHandlePropertyAvailability
    IMHandleAvailability availability = [self TlenPresence2IMHandleAvailability:show];
    [dictionary setObject:[NSNumber numberWithInteger:availability] forKey:IMHandlePropertyAvailability];

    // handle
    [dictionary setObject:from forKey:@"jid"];

    NSLog(@"processPresence: dict %@", dictionary);

    [_delegate connection:self gotPresence:dictionary];
}

- (void)processIq {
    NSLog(@"processIq");

    assert([root.name isEqualToString:@"iq"]);

    NSXMLNode *type = [root attributeForName:@"type"];
    NSXMLNode *id = [root attributeForName:@"id"];
    NSXMLNode *from = [root attributeForName:@"from"];

    if (type == NULL) {
        return;
    }

    if (id == NULL) {
        // pass
    // logged in
    } else if ([[id stringValue] isEqualToString:sessionId]) {
        BOOL success = (type != NULL) && [[type stringValue] isEqualToString:@"result"];
        [_delegate connection:self loggedIn:success];
    // got roster
    } else if ([[id stringValue] isEqualToString:@"GetRoster"] &&
            type != NULL &&
            [[type stringValue] isEqualToString:@"result"]) {
        NSXMLNode *query = [root childAtIndex:0];
        if (query == NULL) return;

        NSMutableArray *buddies = [[NSMutableArray alloc] init];

        for (NSXMLNode *child in [query children]) {
            if (! [[child name] isEqualToString:@"item"])
                continue;
            NSXMLElement *buddy = (NSXMLElement *) child;
//            NSLog(@"buddy %@", buddy);

            NSString *jid = [[buddy attributeForName:@"jid"] objectValue];
            NSString *name = [[buddy attributeForName:@"name"] objectValue];
            if (name == NULL) name = jid;
            NSString *subscription = [[buddy attributeForName:@"subscription"] objectValue];

            NSMutableDictionary *b = [[NSMutableDictionary alloc] init];
            [b setObject:jid forKey:@"jid"];
            [b setObject:[self urldecode:name] forKey:@"name"];
            [b setObject:subscription forKey:@"subscription"];

            // IMHandlePropertyEmailAddress
            [b setObject:jid forKey:IMHandlePropertyEmailAddress];

            // IMHandlePropertyAlias
            [b setObject:[self urldecode:name] forKey:IMHandlePropertyAlias];

            // IMHandlePropertyAuthorizationStatus
            IMHandleAuthorizationStatus authorizationStatus = [self TlenSubscription2IMHandleAuthorizationStatus:subscription];
            [b setObject:[NSNumber numberWithInteger:authorizationStatus] forKey:IMHandlePropertyAuthorizationStatus];

            // IMHandlePropertyAvailability
            // IMHandlePropertyStatusMessage
            // IMHandlePropertyIdleDate
            //
            // IMHandlePropertyFirstName
            // IMHandlePropertyLastName
            // IMHandlePropertyPictureIdentifier
            // IMHandlePropertyPictureData

            // IMHandlePropertyCapabilities
            NSArray *caps = [[NSArray alloc] initWithObjects:IMHandleCapabilityMessaging, IMHandleCapabilityOfflineMessaging, nil];
            [b setObject:caps forKey:IMHandlePropertyCapabilities];

            [buddies addObject:b];
        }

        gotRoster = TRUE;
        [_delegate connection:self gotRoster:buddies];

        // set presence
        [self setPresence];
    }
}

- (const char *)IMSessionAvailability2TlenPresence:(IMSessionAvailability)presence {
    if (presence == IMSessionAvailabilityAway) {
        return "away";
    } else {
        return "available";
    }
}

- (IMHandleAvailability)TlenPresence2IMHandleAvailability:(NSString *)presence {
    NSLog(@"TlenPresence2IMHandleAvailability %@", presence);

    if ([presence isEqualToString:@"available"]) {
        return IMHandleAvailabilityAvailable;
    } else if ([presence isEqualToString:@"chat"]) {
        return IMHandleAvailabilityAvailable;
    } else if ([presence isEqualToString:@"away"]) {
        return IMHandleAvailabilityAway;
    } else if ([presence isEqualToString:@"xa"]) {
        return IMHandleAvailabilityAway;
    } else if ([presence isEqualToString:@"dnd"]) {
        return IMHandleAvailabilityAway;
    } else {
        return IMHandleAvailabilityUnknown;
    }
}

- (IMHandleAuthorizationStatus)TlenSubscription2IMHandleAuthorizationStatus:(NSString *)subscription {
    if ([subscription isEqualToString:@"both"]) {
        return IMHandleAuthorizationStatusAccepted;
    } else {
        return IMHandleAuthorizationStatusDeclined;
    }
}

- (void)setPresence {
    if (! gotRoster) {
        NSLog(@"setPresence skipping");
        return;
    }

    NSString *s;

    NSNumber *isInvisible = [sessionProperties objectForKey:IMSessionPropertyIsInvisible];
    IMSessionAvailability availability = (IMSessionAvailability) [[sessionProperties objectForKey:IMSessionPropertyAvailability] intValue];
    NSString *description = [sessionProperties objectForKey:IMSessionPropertyStatusMessage];

    if ([isInvisible boolValue]) {
        s = @"<presence type='invisible'></presence>";
    } else if (description != NULL) {
        s = [NSString
                stringWithFormat:@"<presence><show>%s</show><status>%s</status></presence>",
                [self IMSessionAvailability2TlenPresence:availability],
                [description UTF8String]
        ];
    } else {
        s = [NSString stringWithFormat:@"<presence><show>%s</show></presence>", [self IMSessionAvailability2TlenPresence:availability]];
    }

    NSLog(@"setPresence %@", s);

    [self write:s];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    NSLog(@"Error %ld, Description: %@, Line: %ld, Column: %ld", [parseError code], [[parser parserError] localizedDescription], [parser lineNumber], [parser columnNumber]);

    [_delegate connection:self parseError:parseError];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventHasSpaceAvailable: {
            /* write bytes to socket */
            break;
        }
        default:
            break;
    }
}

- (void)logout {
    NSString *s = @"</s>";
    gotRoster = FALSE;
    [self write:s];
    [self stopPingTimer];
}

//- (void)destroy {
//    [inputStream close];
//    [outputStream close];
//}

- (void)requestGroupList {
    NSString *s = @"<iq type='get' id='GetRoster'><query xmlns='jabber:iq:roster'></query></iq>";
    [self write:s];
}

- (void)updateSessionProperties:(NSDictionary *)dictionary {
    sessionProperties = dictionary;
    [self setPresence];
}

- (void)sendMessage:(IMServicePlugInMessage *)message toHandle:(NSString *)jid {
    NSLog(@"sendMessage: %@ jid %@", message, jid);

    NSString *msg = [self urlencode:[message.content string]];

    NSString *s = [NSString stringWithFormat:@"<message to='%@' type='chat'><body>%@</body></message>", jid, msg];
    [self write:s];

    [_delegate connection:self messageSent:message from:jid];
}

- (void)startedTyping:(NSString *)handle {
    NSString *s = [NSString stringWithFormat:@"<m to='%@' tp='t'/>", handle];
    [self write:s];
}

- (void)stopedTyping:(NSString *)handle {
    NSString *s = [NSString stringWithFormat:@"<m to='%@' tp='u'/>", handle];
    [self write:s];
}

@end