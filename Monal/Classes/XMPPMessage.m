//
//  XMPPMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "XMPPMessage.h"
#import <monalxmpp/MLContact.h>
#import <monalxmpp/monalxmpp-Swift.h>

@class MLContact;

@interface MLXMLNode()
@property (atomic, strong, readwrite) NSString* element;
@end

@implementation XMPPMessage

NSString* const kMessageChatType = @"chat";
NSString* const kMessageGroupChatType = @"groupchat";
NSString* const kMessageErrorType = @"error";
NSString* const kMessageNormalType = @"normal";
NSString* const kMessageHeadlineType = @"headline";

-(XMPPMessage*) init
{
    self = [super init];
    self.element = @"message";
    [self setXMLNS:@"jabber:client"];
    self.attributes[@"type"] = kMessageChatType;    //default value, can be overwritten later on
    self.id = [[NSUUID UUID] UUIDString];           //default value, can be overwritten later on
    return self;
}

-(XMPPMessage*) initWithType:(NSString*) type to:(NSString*) to
{
    self = [self initWithType:type];
    self.attributes[@"to"] = to;
    return self;
}

-(XMPPMessage*) initToContact:(MLContact*) toContact
{
    self = [self initWithType:(toContact.isMuc ? kMessageGroupChatType : kMessageChatType) to:toContact.contactJid];
    return self;
}

-(XMPPMessage*) initWithType:(NSString*) type
{
    self = [self init];
    self.attributes[@"type"] = type;
    return self;
}

-(XMPPMessage*) initWithXMPPMessage:(XMPPMessage*) msg
{
    self = [self initWithElement:msg.element withAttributes:msg.attributes andChildren:msg.children andData:msg.data];
    return self;
}

//this oerwrites the setter of XMPPStanza
-(void) setId:(NSString*) idval
{
    [super setId:idval];
    //add origin id to indicate we are using uuids for our stanza ids
    //(modify origin id, if already present)
    if([self check:@"{urn:xmpp:sid:0}origin-id"])
        ((MLXMLNode*)[self findFirst:@"{urn:xmpp:sid:0}origin-id"]).attributes[@"id"] = idval;
    else
        [self addChildNode:[[MLXMLNode alloc] initWithElement:@"origin-id" andNamespace:@"urn:xmpp:sid:0" withAttributes:@{@"id":idval} andChildren:@[] andData:nil]];
}

-(void) setBody:(NSString*) messageBody
{
    MLXMLNode* body = [self findFirst:@"body"];
    if(body)
        body.data = messageBody;
    else
        [self addChildNode:[[MLXMLNode alloc] initWithElement:@"body" withAttributes:@{} andChildren:@[] andData:messageBody]];
}

-(void) setOobUrl:(NSString*) link
{
    MLXMLNode* oobElement = [self findFirst:@"{jabber:x:oob}x"];
    MLXMLNode* oobElementUrl = [self findFirst:@"{jabber:x:oob}x/url"];
    if(oobElement && oobElementUrl == nil)
        [oobElement addChildNode:[[MLXMLNode alloc] initWithElement:@"url" withAttributes:@{} andChildren:@[] andData:link]];
    else if(oobElement && oobElementUrl)
        oobElementUrl.data = link;
    else
        [self addChildNode:[[MLXMLNode alloc] initWithElement:@"x" andNamespace:@"jabber:x:oob" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"url" withAttributes:@{} andChildren:@[] andData:link]
        ] andData:nil]];
    [self setBody:link];    //http filetransfers must have a message body equal to the oob link to be recognized as filetransfer
}

-(void) setLMCFor:(NSString*) id
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"replace" andNamespace:@"urn:xmpp:message-correct:0" withAttributes:@{@"id": id} andChildren:@[] andData:nil]];
}

/**
 @see https://xmpp.org/extensions/xep-0184.html
 */
-(void) setReceipt:(NSString*) messageId
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"received" andNamespace:@"urn:xmpp:receipts" withAttributes:@{@"id":messageId} andChildren:@[] andData:nil]];
}

-(void) setDisplayed:(NSString*) messageId
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"displayed" andNamespace:@"urn:xmpp:chat-markers:0" withAttributes:@{@"id":messageId} andChildren:@[] andData:nil]];
}

-(void) setMDSDisplayed:(NSString*) stanzaId withStanzaIdBy:(NSString*) by
{
    [self addChildNode:
        [[MLXMLNode alloc] initWithElement:@"displayed" andNamespace:@"urn:xmpp:mds:displayed:0" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"stanza-id" andNamespace:@"urn:xmpp:sid:0" withAttributes:@{
                @"by": by,
                @"id": stanzaId,
            } andChildren:@[] andData:nil]
        ] andData:nil]
    ];
}

-(void) setStoreHint
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"store" andNamespace:@"urn:xmpp:hints"]];
}

-(void) setNoStoreHint
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"no-store" andNamespace:@"urn:xmpp:hints"]];
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"no-storage" andNamespace:@"urn:xmpp:hints"]];
}

//isaCloud: the poll element (urn:fluux:poll:0) of a poll message, built from the poll JSON (see Polls.swift). The flags go in only when they are true
//(absence means false, as in the Fluux client); the fallback body (XEP-0428 style, `<fallback for="urn:fluux:poll:0"><body/></fallback>`) tells the clients
//that do not know the poll to show the body of the message. See docs/implementacao-enquetes-ios.md, 2.1
-(void) addPollFromJSON:(NSString*) pollJSON
{
    NSDictionary* fields = [ISACloudPolls pollFieldsFromJSON:pollJSON];
    if(fields == nil)
    {
        DDLogWarn(@"Not adding a poll element: the poll JSON is not valid");
        return;
    }
    MLXMLNode* pollNode = [[MLXMLNode alloc] initWithElement:@"poll" andNamespace:@"urn:fluux:poll:0"];
    if([fields[@"allowMultiple"] boolValue])
        pollNode.attributes[@"allow-multiple"] = @"true";
    if([fields[@"hideResults"] boolValue])
        pollNode.attributes[@"hide-results"] = @"true";
    if(fields[@"deadline"] != nil)
        pollNode.attributes[@"deadline"] = fields[@"deadline"];
    [pollNode addChildNode:[[MLXMLNode alloc] initWithElement:@"title" andData:fields[@"title"]]];
    if(fields[@"description"] != nil)
        [pollNode addChildNode:[[MLXMLNode alloc] initWithElement:@"description" andData:fields[@"description"]]];
    for(NSDictionary* option in fields[@"options"])
        [pollNode addChildNode:[[MLXMLNode alloc] initWithElement:@"option" withAttributes:@{
            @"emoji": option[@"emoji"],
        } andChildren:@[] andData:option[@"label"]]];
    [self addChildNode:pollNode];
    [self addPollFallbackFor:@"urn:fluux:poll:0"];
}

//isaCloud: the closing of a poll (`<poll-closed message-id="…">`, the message-id is the client id of the poll message), built from the closing JSON.
//Each option has a tally (emoji, label, count and voters as a CSV of nicks; the voters attribute is left out when nobody has a nick)
-(void) addPollClosedFromJSON:(NSString*) closedJSON
{
    NSDictionary* fields = [ISACloudPolls closedFieldsFromJSON:closedJSON];
    if(fields == nil)
    {
        DDLogWarn(@"Not adding a poll-closed element: the closing JSON is not valid");
        return;
    }
    NSMutableArray* children = [NSMutableArray new];
    [children addObject:[[MLXMLNode alloc] initWithElement:@"title" andData:fields[@"title"]]];
    if(fields[@"description"] != nil)
        [children addObject:[[MLXMLNode alloc] initWithElement:@"description" andData:fields[@"description"]]];
    for(NSDictionary* line in fields[@"tally"])
    {
        NSMutableDictionary* attributes = [NSMutableDictionary new];
        attributes[@"emoji"] = line[@"emoji"];
        attributes[@"label"] = line[@"label"];
        attributes[@"count"] = [NSString stringWithFormat:@"%@", line[@"count"]];
        if([line[@"voters"] length] > 0)
            attributes[@"voters"] = line[@"voters"];
        [children addObject:[[MLXMLNode alloc] initWithElement:@"tally" withAttributes:attributes andChildren:@[] andData:nil]];
    }
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"poll-closed" andNamespace:@"urn:fluux:poll:0" withAttributes:@{
        @"message-id": fields[@"messageId"],
    } andChildren:children andData:nil]];
    [self addPollFallbackFor:@"urn:fluux:poll:0"];
}

-(void) addPollFallbackFor:(NSString*) pollNamespace
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"fallback" andNamespace:@"urn:xmpp:fallback:0" withAttributes:@{
        @"for": pollNamespace,
    } andChildren:@[[[MLXMLNode alloc] initWithElement:@"body"]] andData:nil]];
}

@end
