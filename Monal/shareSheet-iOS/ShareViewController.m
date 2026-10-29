//
//  ShareViewController.m
//  shareSheet
//
//  Created by Anurodh Pokharel on 9/10/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "ShareViewController.h"
#import "shareSheet-Swift.h"

#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLFileTransfer.h>
#import <monalxmpp/IPC.h>

#import <MapKit/MapKit.h>
#import <MobileCoreServices/MobileCoreServices.h>

@import Intents;
@import UniformTypeIdentifiers;

@interface ShareViewController ()

@property (nonatomic, strong) MLContact* intentContact;

@end

@implementation ShareViewController

+(void) initialize
{
    [HelperTools initSystem];
    
    //resume logging and other core tasks
    [HelperTools signalResumption];
    
    //init IPC
    [IPC initializeForProcess:@"ShareSheetExtension"];
    
    //log startup
    DDLogInfo(@"Share Sheet Extension started: %@", [HelperTools appBuildVersionInfoFor:MLVersionTypeLog]);
    [DDLog flushLog];
    
    MLAssert([HelperTools deviceUUIDAccessibleOrAllowedEmpty:YES] == YES, @"device UUID should always be accessible or empty when using the share extension!");
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    
    DDLogInfo(@"Extension context: %@", self.extensionContext);
    DDLogDebug(@"Raw extension context intent: %@", self.extensionContext.intent);
    if(self.extensionContext.intent != nil && [self.extensionContext.intent isKindOfClass:[INSendMessageIntent class]])
    {
        INSendMessageIntent* intent = (INSendMessageIntent*)self.extensionContext.intent;
        DDLogDebug(@"Got usable intent: %@", intent);
        self.intentContact = [HelperTools unserializeData:[intent.conversationIdentifier dataUsingEncoding:NSISOLatin1StringEncoding]];
        DDLogInfo(@"Extracted intent contact: %@", self.intentContact);
        [self.intentContact refresh];       //make sure we are up to date
    }
    
    //the picker itself is SwiftUI (same look as the app's "Forward…" screen), this view controller only hosts it
    __weak __typeof(self) weakSelf = self;
    UIViewController* picker = [SharePickerBridge makeViewControllerWithSend:^(MLContact* recipient, NSString* message) {
        [weakSelf enqueuePayloadsForRecipient:recipient message:message];
    } andCancel:^{
        [weakSelf cancelShare];
    } initialRecipient:self.intentContact];
    
    [self addChildViewController:picker];
    picker.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:picker.view];
    [NSLayoutConstraint activateConstraints:@[
        [picker.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [picker.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [picker.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [picker.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [picker didMoveToParentViewController:self];
}

-(void) cancelShare
{
    [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
}

-(NSExtensionItem*) filterItems:(NSArray*) items
{
    for(NSExtensionItem* item in items)
        for(NSItemProvider* provider in item.attachments)
        {
            //public.data, public.file-url, or com.apple.pkpass
            if([provider hasItemConformingToTypeIdentifier:UTTypeData.identifier])
                return item;
            else if([provider hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier])
                return item;
            else if([provider hasItemConformingToTypeIdentifier:@"com.apple.pkpass"])
                return item;
        }
    return items.firstObject;       //fallback, should normally not be needed
}

//called by the SwiftUI picker with the chosen destination: extract everything that was shared and queue it for the main app
-(void) enqueuePayloadsForRecipient:(MLContact*) recipient message:(NSString*) shareText
{
    DDLogVerbose(@"input items: %@", self.extensionContext.inputItems);
    
    //filter items for first one matching public.data, public.file-url, or com.apple.pkpass (Signal does the same)
    //TODO: should we instead simply flatten all attachments of all items into one attachments array instead, like other apps seem to do it?
    NSExtensionItem* item = [self filterItems:self.extensionContext.inputItems];
    
    //convert all attachments to fulfilled promises
    DDLogVerbose(@"Attachments = %@", item.attachments);

    //process all items first (tmpfiles of unused ones will be autodeleted by our tmpfile cleanup)
    NSMutableArray<AnyPromise*>* attachments = [NSMutableArray new];
    for(NSItemProvider* provider in item.attachments)
        //extract item data
        [attachments addObject:[AnyPromise promiseWithValue:provider].then(^id(NSItemProvider* provider) {
            DDLogDebug(@"Handling: %@", provider);
            return [HelperTools handleUploadItemProvider:provider].then(^id(NSMutableDictionary* payload) {
                return PMKManifold(provider, payload);
            });
        //add recipient information
        }).then(^id(NSItemProvider* provider, NSMutableDictionary* payload) {
            DDLogDebug(@"Got handleUploadItemProvider callback with payload: %@ for provider: %@", payload, provider);
            if(payload == nil)      //short circuit
                return nil;
            payload[@"account_id"] = recipient.accountID;
            payload[@"recipient"] = recipient.contactJid;
            return PMKManifold(provider, payload);
        //filter out all bplist items already contained in the contentText field (google youtube and google maps apps)
        }).then(^id(NSItemProvider* provider, NSDictionary* payload) {
            if(payload == nil)      //short circuit
                return nil;
            
            //text shares (not text files) are often also shared via comment field
            //--> special handling below, everything else is just returned
            //(we have to check if we landed in the last text file block inside handleUploadItemProvider,
            //because hasItemConformingToTypeIdentifier would also match for UTTypeURL etc.)
            if(![payload[@"uttype"] isEqualToString:UTTypePlainText.identifier])
                return payload;
            
            //ignore text shares, if they contain the same contents as the comment field
            if(shareText && [shareText length] > 0 && [payload[@"data"] isKindOfClass:[NSString class]] && [shareText isEqualToString:payload[@"data"]])
            {
                DDLogWarn(@"Ignoring plain text payload because already sent via comment field");
                return nil;
            }
            
            //urls or other plaintext transfered as bplist
            return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
                [provider loadItemForTypeIdentifier:UTTypePlainText.identifier options:nil completionHandler:^(NSString* item, NSError* _Null_unspecified error) {
                    if(item != nil && item.length > 0 && error == nil)
                    {
                        if(shareText && [shareText length] > 0 && item != nil && [shareText isEqualToString:item])
                        {
                            DDLogWarn(@"Ignoring serialized NSString payload because already sent via comment field");
                            return resolve(nil);
                        }
                        else
                        {
                            NSMutableDictionary* payload = [NSMutableDictionary new];
                            payload[@"account_id"] = recipient.accountID;
                            payload[@"recipient"] = recipient.contactJid;
                            payload[@"type"] = @"text";
                            payload[@"data"] = item;
                            DDLogDebug(@"Adding serialized NSString payload: %@", payload);
                            return resolve(payload);
                        }
                    }
                    else
                        resolve(payload);
                }];
            }];
        })];
    
    //make sure we only process non-nil payloads
    PMKWhen(attachments).then(^id(NSArray* payloads) {
        return arrayComprehension(payloads, ^id(id e) { return nilExtractor(e); });
    //finally filter for attachments we really want (signalapp style)
    }).then(^id(NSArray* payloads) {
        uint32_t saved = 0;
        NSMutableSet<NSString*>* uttypes = [NSMutableSet new];
        for(NSDictionary* payload in payloads)
            [uttypes addObject:payload[@"uttype"]];
        
        //add the contentText as normal message payload, if given
        if(shareText && [shareText length] > 0)
        {
            DDLogInfo(@"Adding contentText as text message...");
            NSMutableDictionary* payload = [NSMutableDictionary new];
            payload[@"account_id"] = recipient.accountID;
            payload[@"recipient"] = recipient.contactJid;
            payload[@"type"] = @"text";
            payload[@"data"] = shareText;
            DDLogDebug(@"Adding shareSheet comment payload: %@", payload);
            [[DataLayer sharedInstance] addShareSheetPayload:payload];
            saved++;
        }
        
        //mapkit items are superior above all others (urls, files, text): ignore everything else
        if([uttypes containsObject:@"com.apple.mapkit.map-item"])
        {
            for(NSDictionary* payload in payloads)
                if(payload[@"error"] == nil && [payload[@"uttype"] isEqualToString:@"com.apple.mapkit.map-item"])
                {
                    DDLogInfo(@"Adding geo special shareSheet payload(%u): %@", saved, payload);
                    [[DataLayer sharedInstance] addShareSheetPayload:payload];
                    saved++;
                    return PMKManifold(@(saved), @[]);     //empty list --> no error handling (we extracted the map item, thats all we need)
                }
        }
        //contacts are also special: ignore everything else
        if([uttypes containsObject:UTTypeContact.identifier])
        {
            for(NSDictionary* payload in payloads)
                if(payload[@"error"] == nil && [payload[@"uttype"] isEqualToString:UTTypeContact.identifier])
                {
                    DDLogInfo(@"Adding contact special shareSheet payload(%u): %@", saved, payload);
                    [[DataLayer sharedInstance] addShareSheetPayload:payload];
                    saved++;
                    return PMKManifold(@(saved), @[]);     //empty list --> no error handling (we extracted the map item, thats all we need)
                }
        }
        
        //try to use all files (images, videos, simple files)...
        for(NSDictionary* payload in payloads)
            if(payload[@"error"] == nil && ([payload[@"type"] isEqualToString:@"image"] || [payload[@"type"] isEqualToString:@"file"] || [payload[@"type"] isEqualToString:@"audiovisual"]))
            {
                DDLogInfo(@"Adding %@ shareSheet payload(%u): %@", payload[@"type"], saved, payload);
                [[DataLayer sharedInstance] addShareSheetPayload:payload];
                saved++;
            }
//         //...and additionally use urls if no files were found...
//         if(saved == 0)
        //...and additionally use urls...
        if(YES)
        {
            for(NSDictionary* payload in payloads)
                if(payload[@"error"] == nil && [payload[@"type"] isEqualToString:@"url"])
                {
                    DDLogInfo(@"Adding %@ shareSheet payload(%u): %@", payload[@"type"], saved, payload);
                    [[DataLayer sharedInstance] addShareSheetPayload:payload];
                    saved++;
                    break;          //use only the first url
                }
        }
        //...finally simply use everything provided, if neither a file nor url could be found
        if(saved == 0)
        {
            for(NSDictionary* payload in payloads)
            {
                DDLogInfo(@"Adding any (%@) shareSheet payload(%u): %@", payload[@"type"], saved, payload);
                [[DataLayer sharedInstance] addShareSheetPayload:payload];
                saved++;
            }
        }
        
        //return saved payload count and full payload list to next stage for error handling
        return PMKManifold(@(saved), payloads);
    //extract all errors and warn the user about it, this resolves once the user dismisses the error
    }).then(^id(NSNumber* saved, NSArray* payloads) {
        return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
            //extract error descriptions
            NSArray* errorTexts = arrayComprehension(payloads, ^id(NSDictionary* payload) {
                if(payload[@"error"] == nil)
                    return nil;
                DDLogError(@"Could not save payload for sending: %@", payload);
                return [payload[@"error"] localizedDescription];
            });
            
            if(errorTexts.count == 0)
                return resolve(saved);
            
            //build alert message
            NSString* message = [NSString stringWithFormat:NSLocalizedString(@"isaCloud was not able to send any of your attachments: %@", @""), errorTexts];
            if(saved.unsignedIntValue > 0)
                message = [NSString stringWithFormat:NSLocalizedString(@"isaCloud was not able to send some of your attachments: %@", @""), errorTexts];
            
            UIAlertController* unknownItemWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not send", @"")
                                                                        message:message preferredStyle:UIAlertControllerStyleAlert];
            [unknownItemWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Dismiss", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [unknownItemWarning dismissViewControllerAnimated:YES completion:^{
                    resolve(saved);
                }];
            }]];
            [self presentViewController:unknownItemWarning animated:YES completion:nil];
        }];
    //then open the mainapp if we actually managed to extract anything sendable
    }).then(^(NSNumber* saved) {
        DDLogInfo(@"Got %@ saved share items, opening the main app now...", saved);
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:^(BOOL expired __unused) {
            if(saved.unsignedIntValue > 0)
                [self openMainApp];
            [HelperTools signalSuspension];
            //make sure the next start of this extension is a fresh one (like we already do with the NSE appex)
            createTimer(0.250, (^{
                DDLogInfo(@"Committing suicide...");
                exit(0);
            }));
        }];
    });
}

-(void) openURL:(NSURL*) url
{
    UInt16 iterations = 0;
    SEL openURLSelector = NSSelectorFromString(@"openURL:");
    UIResponder* responder = self;
    while((responder = [responder nextResponder]) != nil && iterations++ < 16)
        if([responder respondsToSelector:openURLSelector] == YES)
        {
            UIApplication* app = (UIApplication*)responder;
            if(app != nil)
            {
                [app openURL:url options:@{} completionHandler:nil];
                break;
            }
        }
}

-(void) openMainApp
{
    DDLogInfo(@"Now opening mainapp via %@...", kMonalOpenURL);
    NSURL* mainAppUrl = kMonalOpenURL;
    [self openURL:mainAppUrl];
}

@end
