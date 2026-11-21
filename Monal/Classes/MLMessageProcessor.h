//
//  MLMessageProcessor.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/1/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/xmpp.h>
#import "XMPPMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class MLOMEMO;
@class xmpp;

@interface MLMessageProcessor : NSObject

/**
 Process a message, persist it and post relevant notifications
 */
+(MLMessage* _Nullable) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode forAccount:(xmpp*) account;
+(MLMessage* _Nullable) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode forAccount:(xmpp*) account withHistoryId:(NSNumber* _Nullable) historyId;

/**
 isaCloud: the fields of the <poll> element (urn:fluux:poll:0) of a message, as ISACloudPolls wants them; empty if there is none. Used by processMessage and the unit tests
 */
+(NSDictionary*) pollFieldsFromMessageNode:(MLXMLNode*) messageNode;
/**
 isaCloud: the fields of the <poll-closed> element (urn:fluux:poll:0) of a message, as ISACloudPolls wants them; empty if there is none
 */
+(NSDictionary*) pollClosedFieldsFromMessageNode:(MLXMLNode*) messageNode;

@end

NS_ASSUME_NONNULL_END
