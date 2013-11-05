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

    NSLog(@"write: %s (length %lu)", c, len);

    [outputStream write:(uint8_t const *) c maxLength:len];
}

- (void)login:(NSString *)_username password:(NSString *)_password {
    username = _username;
    password = _password;

    [self initStream:@"s1.tlen.pl" port:443];

    NSString *s = @"<s v='7'>\n";
    [self write:s];
}

- (void)parser:(NSXMLParser *)parser
        didStartElement:(NSString *)elementName
        namespaceURI:(NSString *)namespaceURI
        qualifiedName:(NSString *)qName
        attributes:(NSDictionary *)attributeDict {
    NSLog(@"didStartElement: %@, attributeDict: %@", elementName, attributeDict);

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
        NSLog(@"sessionId %@ hash %s", sessionId, hash);

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
    NSLog(@"foundCharacters: %@", string);

//    assert(currentElement != NULL);

    if (currentElement != NULL) {
        NSXMLNode *xmlNode = [NSXMLNode textWithStringValue:string];
        [currentElement addChild:xmlNode];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    NSLog(@"didEndElement: %@", elementName);

    NSLog(@"currentElement %@", currentElement);

    // special case, ending <s> tag
    if ([elementName isEqualToString:@"s"] && currentElement == NULL) {
        [_delegate connection:self loggedOut:TRUE];
        return;
    }

    assert(currentElement != NULL);

    if ([root.name isEqualToString:elementName]) {
        NSLog(@"processing action %@", root);
        [self processResponse];
        root = NULL;
        currentElement = NULL;
    } else if ([currentElement.name isEqualToString:elementName]) {
        currentElement = (NSXMLElement *) [currentElement parent];
    }

    NSLog(@"root %@", root);
    NSLog(@"after currentElement %@", currentElement);
}

- (void)processResponse {
    NSLog(@"processResponse: root=%@", root);

    assert(root != NULL);

    NSString *s = root.name;

    if ([s isEqualToString:@"iq"]) {
        [self processIq];
    } else {
        NSLog(@"unknown XML");
    }
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

//        IMGroupListPermissions allGroupPermissions = IMGroupListCanReorderGroup | IMGroupListCanRenameGroup | IMGroupListCanAddNewMembers | IMGroupListCanRemoveMembers | IMGroupListCanReorderMembers;
//        NSArray *groups = [NSArray arrayWithObjects:
//                [NSDictionary dictionaryWithObjectsAndKeys:
//                        IMGroupListNameKey, IMGroupListDefaultGroup, IMGroupListPermissionsKey,
//                        [NSNumber numberWithUnsignedInteger:IMGroupListCanAddNewMembers],
//                        IMGroupListHandlesKey, [self usersForGroup:nil],
//                        nil],
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

//            NSLog(@"b %@", b);
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

- (void)setPresence {
    if (! gotRoster) {
        NSLog(@"setPresence skipping");
        return;
    }

    NSString *s;

    NSNumber *isInvisible = [sessionProperties objectForKey:IMSessionPropertyIsInvisible];
    IMSessionAvailability availability = (IMSessionAvailability) [[sessionProperties objectForKey:IMSessionPropertyAvailability] intValue];
    NSString *description = [sessionProperties objectForKey:IMSessionPropertyStatusMessage];

    NSLog(@"setPresence isInvisible %d", [isInvisible boolValue]);
    NSLog(@"setPresence availability %d", availability);

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
    [self write:s];
}

- (void)destroy {
    [inputStream close];
    [outputStream close];
}

- (void)requestGroupList {
    NSString *s = @"<iq type='get' id='GetRoster'><query xmlns='jabber:iq:roster'></query></iq>";
    [self write:s];
}

- (void)updateSessionProperties:(NSDictionary *)dictionary {
    sessionProperties = dictionary;
    [self setPresence];
}

@end