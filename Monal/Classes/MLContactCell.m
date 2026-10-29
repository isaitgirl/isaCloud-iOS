//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLMessage.h>
#import <monalxmpp/DataLayer.h>
#import "MLXEPSlashMeHandler.h"
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/xmpp.h>
#import <monalxmpp/MLImageManager.h>
#import <monalxmpp/MLFiletransferInfo.h>
#import <QuartzCore/QuartzCore.h>

@interface MLContactCell()

@end

@implementation MLContactCell
{
    //isaCloud: the jid of the account this chat belongs to, under the name, while more than one account is enabled
    UILabel* _accountJid;
    //isaCloud: the "@" shown before the notification-type bell when the chat has unread notifications/mentions
    UILabel* _atMark;
    //isaCloud: cached result of the red/gray badge rule, computed once per cell update (it queries the database for mentions)
    BOOL _badgeIsGray;
    //isaCloud: whether the next preview text should be highlighted (red counter: notification or mention)
    BOOL _previewHighlight;
    NSLayoutConstraint* _statusTopConstraint;
}

-(void) awakeFromNib
{
    [super awakeFromNib];
    
    //isaCloud: created in code to not touch the xib; the status label is moved down by its top constraint when the line is shown
    _accountJid = [UILabel new];
    _accountJid.translatesAutoresizingMaskIntoConstraints = NO;
    _accountJid.font = [UIFont systemFontOfSize:12];
    //a bit darker than the last message preview (light gray, set by the chat list), in light and dark mode
    _accountJid.textColor = [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return [UIColor colorWithWhite:traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.55 : 0.4 alpha:1.0];
    }];
    _accountJid.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _accountJid.hidden = YES;
    [self.contentView addSubview:_accountJid];
    [NSLayoutConstraint activateConstraints:@[
        [_accountJid.leadingAnchor constraintEqualToAnchor:self.displayName.leadingAnchor],
        [_accountJid.trailingAnchor constraintEqualToAnchor:self.displayName.trailingAnchor],
        [_accountJid.topAnchor constraintEqualToAnchor:self.displayName.bottomAnchor constant:1],
    ]];
    for(NSLayoutConstraint* constraint in self.contentView.constraints)
        if(constraint.firstItem == self.statusText && constraint.firstAttribute == NSLayoutAttributeTop)
            _statusTopConstraint = constraint;
    
    //isaCloud: the "@" that marks a chat with unread notifications/mentions, just before the notification-type bell
    _atMark = [UILabel new];
    _atMark.translatesAutoresizingMaskIntoConstraints = NO;
    _atMark.text = @"@";
    _atMark.font = [UIFont boldSystemFontOfSize:13];
    //isaCloud: the same pink as the notification-type bell
    _atMark.textColor = [UIColor colorNamed:@"isaCloudPink"] ?: [UIColor systemPinkColor];
    _atMark.hidden = YES;
    [self.contentView addSubview:_atMark];
    [NSLayoutConstraint activateConstraints:@[
        [_atMark.trailingAnchor constraintEqualToAnchor:self.mentionBadge.leadingAnchor constant:-3],
        [_atMark.centerYAnchor constraintEqualToAnchor:self.mentionBadge.centerYAnchor],
    ]];
}

-(void) showAccountJid:(NSString* _Nullable) accountJid
{
    if(accountJid.length == 0)
    {
        _accountJid.hidden = YES;
        _statusTopConstraint.constant = 2;
        return;
    }
    //the line sits next to the name; the last message keeps a bit more distance, below it
    _accountJid.text = accountJid;
    _accountJid.hidden = NO;
    _statusTopConstraint.constant = 19;
    //without a last message the name is centered: use the top aligned one to leave room for the line
    self.centeredDisplayName.hidden = YES;
    self.displayName.hidden = NO;
}

-(void) initCell:(MLContact*) contact withLastMessage:(MLMessage* _Nullable) lastMessage
{
    [self showDisplayName:contact.contactDisplayName];
    [self setPinned:contact.isPinned];
    [self setCount:(long)contact.unreadCount];
    [self setBadgeColorForContact:contact];
    //isaCloud: the highlight has to be known before the preview is built: showStatusText: rewrites the label and would
    //throw away attributes applied afterwards (it compares against the label's own original text)
    _previewHighlight = contact.unreadCount > 0 && !_badgeIsGray;
    [self displayLastMessage:lastMessage forContact:contact];
    
    //isaCloud: the avatar may be decoded in background now, so use the placeholder returned right away and swap it when the
    //real image arrives (without this the reused cell would keep the previous contact's avatar until the decode finished)
    UIImage* immediateIcon = [[MLImageManager sharedInstance] getIconForContact:contact withCompletion:^(UIImage *image) {
        if(image != nil)
            self.userImage.image = image;
    }];
    if(immediateIcon != nil)
        self.userImage.image = immediateIcon;
    
    if(contact.isMuc && contact.isMentionOnly)
    {
        self.muteBadge.hidden = YES;
        self.mentionBadge.hidden = NO;
    }
    else
    {
        self.muteBadge.hidden = !contact.isMuted;
        self.mentionBadge.hidden = YES;
    }
    
    //isaCloud: a red unread counter (notification or mention) makes the preview bold and puts a "@" before the bell
    [self applyUnreadHighlightForContact:contact];
}

//isaCloud: bold preview + "@" for chats with unread notifications/mentions (the red counter, not the gray one)
-(void) applyUnreadHighlightForContact:(MLContact*) contact
{
    BOOL highlight = contact.unreadCount > 0 && !_badgeIsGray;
    self.previewHighlighted = highlight;
    //the "@" only makes sense next to the bell that tells the notification type of the chat:
    //without that bell (a normal 1:1 chat, for instance) the bold preview is the only marker
    _atMark.hidden = !(highlight && (!self.muteBadge.hidden || !self.mentionBadge.hidden));
}

//isaCloud: bold and near black (not pure black, so it does not look like the chat name) for a preview of a chat with a red counter
//isaCloud: the color of a highlighted preview (Isadora's #373736): near black, but not the same as the chat name
+(UIColor*) previewHighlightColor
{
    return [UIColor colorWithRed:0x37/255.0 green:0x37/255.0 blue:0x36/255.0 alpha:1.0];
}

-(void) highlightPreviewText:(NSMutableAttributedString*) text
{
    //isaCloud: only the color changes: bold made the preview look bigger than the chat name on the iPhone
    //the color has to be an attribute: the chat list sets statusText.textColor after configuring the cell (light gray,
    //or white for the selected chat), and a label textColor does not override attributes of the attributed string
    [text addAttribute:NSForegroundColorAttributeName value:[MLContactCell previewHighlightColor] range:NSMakeRange(0, text.length)];
}

-(void) displayLastMessage:(MLMessage* _Nullable) lastMessage forContact:(MLContact*) contact
{
    if(lastMessage)
    {
        if(lastMessage.timestamp)
        {
            self.time.text = [self formattedDateWithSource:lastMessage.timestamp];
            self.time.hidden = NO;
        }
        else
            self.time.hidden = YES;
        
        if(lastMessage.retracted)
        {
            NSString* retractedStatus = NSLocalizedString(@"This message got retracted", @"");
            [self showStatusTextItalic:retractedStatus withItalicRange:NSMakeRange(0, retractedStatus.length)];
            return;
        }
        else if ([lastMessage.messageType isEqualToString:kMessageTypeMessageDraft])
        {
            NSString* draftPreviewPrefix = NSLocalizedString(@"Draft:", @"");
            NSString* draftPreview = [NSString stringWithFormat:@"%@ %@", draftPreviewPrefix, lastMessage.messageText];
            [self showStatusTextItalic:draftPreview withItalicRange:NSMakeRange(0, draftPreviewPrefix.length)];
            return;
        }
        
        NSString* senderOfLastGroupMsg;     // set to nick of sender in a group chat, if this is a group chat (1:1 MUST be nil)
        if(lastMessage.isMuc)
            senderOfLastGroupMsg = lastMessage.contactDisplayName;
        
        if([lastMessage.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            [self showStatusText:NSLocalizedString(@"🔗 A Link", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        else if([lastMessage.messageType isEqualToString:kMessageTypeGeo])
            [self showStatusText:NSLocalizedString(@"📍 A Location", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        else if([lastMessage.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            if(lastMessage.fileInfo.isImage)
                [self showStatusText:NSLocalizedString(@"📷 An Image", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if(lastMessage.fileInfo.isAudio)
                [self showStatusText:NSLocalizedString(@"🎵 An Audiomessage", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if(lastMessage.fileInfo.isVideo)
                [self showStatusText:NSLocalizedString(@"🎥 A Video", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if(lastMessage.fileInfo.isPDF)
                [self showStatusText:NSLocalizedString(@"📄 A Document", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else
                [self showStatusText:NSLocalizedString(@"📁 A File", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        }
        else
        {
            if([lastMessage.messageText hasPrefix:@"/me "])
            {
                NSString* replacedMessageText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithMessage:lastMessage];
                [self showStatusTextItalic:replacedMessageText withItalicRange:NSMakeRange(0, replacedMessageText.length)];
            }
            else
            {
                //isaCloud: a forwarded text starts with a line like "<arrow> Forwarded": the preview shows it on one line, with the text after it
                //(otherwise only the label would be seen). Same rule as MessageForward.split in the app: a short first line that starts with the arrow.
                NSString* previewText = lastMessage.messageText;
                NSRange lineBreak = [previewText rangeOfString:@"\n"];
                if(lineBreak.location != NSNotFound && lineBreak.location <= 30 && lineBreak.location + 1 < previewText.length
                   && ([previewText hasPrefix:@"\u21AA"] || [previewText hasPrefix:@"\u21B7"] || [previewText hasPrefix:@"\u27A6"]))
                    previewText = [previewText stringByReplacingCharactersInRange:lineBreak withString:@" "];
                [self showStatusText:previewText inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            }
        }
    }
    else
    {
        [self showStatusText:nil inboundDir:NO fromUser:nil];
        self.time.hidden = YES;
    }
}

-(void) showStatusText:(NSString *) text inboundDir:(BOOL) inboundDir fromUser:(NSString* _Nullable) fromUser
{
    NSString* statusMessage = @"";
    if(inboundDir == NO)
        statusMessage = [NSString stringWithFormat:@"%@ ", NSLocalizedString(@"Me:", @"Prefix for own messages in chat overview")];
    else if(inboundDir == YES && fromUser != nil && fromUser.length > 0)
        statusMessage = [NSString stringWithFormat:@"%@: ", fromUser];

    // set range of "Me" prefix that should be gray
    NSRange meAttrRange = NSMakeRange(0, statusMessage.length);

    if(text != nil)
    {
        statusMessage = [statusMessage stringByAppendingString:text];
        // set attribute settings
        NSMutableAttributedString* attrStatusText = [[NSMutableAttributedString alloc] initWithString:statusMessage];
        [attrStatusText addAttribute:NSForegroundColorAttributeName value:[UIColor lightGrayColor] range:meAttrRange];

        if(_previewHighlight)
            [self highlightPreviewText:attrStatusText];
        if(![attrStatusText isEqualToAttributedString:self.statusText.originalAttributedText])
        {
            // only update UI if needed
            self.statusText.attributedText = attrStatusText;
            [self setStatusTextLayout:text];
        }
    }
    else
    {
        self.statusText.text = nil;
    }
}

-(void) showStatusTextItalic:(NSString*) text withItalicRange:(NSRange) italicRange
{
    UIFont* italicFont = [UIFont italicSystemFontOfSize:self.statusText.font.pointSize];
    NSMutableAttributedString* italicString = [[NSMutableAttributedString alloc] initWithString:text];
    [italicString addAttribute:NSFontAttributeName value:italicFont range:italicRange];

    if(![italicString isEqualToAttributedString:self.statusText.originalAttributedText])
    {
        self.statusText.attributedText = italicString;
        [self setStatusTextLayout:text];
    }
}

-(void) setStatusTextLayout:(NSString*) text
{
    if(text)
    {
        self.centeredDisplayName.hidden = YES;
        self.displayName.hidden = NO;
        self.statusText.hidden = NO;
    }
    else
    {
        self.centeredDisplayName.hidden = NO;
        self.displayName.hidden=YES;
        self.statusText.hidden=YES;
    }
}

-(void) showDisplayName:(NSString *) name
{
    if(self.displayName && ![self.displayName.text isEqualToString:name])
    {
        self.centeredDisplayName.text = name;
        self.displayName.text = name;
    }
}

-(void) setCount:(long)count
{
    if(count > 0)
    {
        // show number of unread messages
        [self.badge setTitle:[NSString stringWithFormat:@"%ld", (long)count] forState:UIControlStateNormal];
        self.badge.hidden = NO;
    }
    else
    {
        // hide number of unread messages
        [self.badge setTitle:@"" forState:UIControlStateNormal];
        self.badge.hidden = YES;
    }
}

//isaCloud: the unread counter is gray when the chat is muted or a mention-only group has no unread mention for us
-(BOOL) shouldShowGrayBadgeForContact:(MLContact*) contact
{
    //a muted chat is always gray, even when one of its unread messages mentions us
    if(contact.isMuted)
        return YES;
    //one to one chats and groups with all notifications are red
    if(!(contact.isMuc && contact.isMentionOnly))
        return NO;
    //a mention-only group without unread messages has no visible counter anyway
    if(contact.unreadCount <= 0)
        return YES;
    //the names are the same ones the notification manager uses to detect a mention
    NSMutableArray<NSString*>* names = [NSMutableArray new];
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:contact.contactJid forAccount:contact.accountID];
    [names addObject:nick ?: @""];
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getEnabledAccountForID:contact.accountID];
    if(xmppAccount)
    {
        NSString* ownJid = xmppAccount.connectionProperties.identity.jid;
        [names addObject:[MLContact ownDisplayNameForAccount:xmppAccount] ?: @""];
        [names addObject:[HelperTools splitJid:ownJid][@"user"] ?: @""];
        [names addObject:ownJid ?: @""];
    }
    BOOL mentioned = [[DataLayer sharedInstance] hasUnreadMentionInMuc:contact.contactJid forAccount:contact.accountID withNames:names];
    return !mentioned;
}

//isaCloud: cells are reused, so the image is always set again to avoid a gray counter staying in a red one
-(void) setBadgeColorForContact:(MLContact*) contact
{
    UIImage* bubble = [UIImage imageNamed:@"NotificationBubble"];
    _badgeIsGray = [self shouldShowGrayBadgeForContact:contact];
    if(_badgeIsGray)
        bubble = [bubble imageWithTintColor:UIColor.systemGrayColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.badge setBackgroundImage:bubble forState:UIControlStateNormal];
}

-(void) setPinned:(BOOL) pinned
{
    self.isPinned = pinned;
    
    if(pinned) {
        self.pinBadge.hidden = NO;
    } else {
        self.pinBadge.hidden = YES;
    }
}

#pragma mark - date
-(NSString*) formattedDateWithSource:(NSDate*) sourceDate
{
    NSDateFormatter* dateFormatter = [NSDateFormatter new];
    if([[NSCalendar currentCalendar] isDateInToday:sourceDate])
    {
        //today just show time
        [dateFormatter setDateStyle:NSDateFormatterNoStyle];
        [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    }
    else
    {
        // note: if it isnt the same day we want to show the full day
        [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
        //no more need for seconds
        [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
    }
    NSString* dateString = [dateFormatter stringFromDate:sourceDate];
    return dateString ? dateString : @"";
}

@end
