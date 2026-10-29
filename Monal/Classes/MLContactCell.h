//
//  MLContactCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//
#import "MLAttributedLabel.h"
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLMessage.h>

@interface MLContactCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UILabel* _Nullable displayName;
@property (nonatomic, weak) IBOutlet UILabel* _Nullable centeredDisplayName;
@property (nonatomic, weak) IBOutlet UILabel* _Nullable time;

@property (nonatomic, weak) IBOutlet MLAttributedLabel* _Nullable statusText;
@property (nonatomic, weak) IBOutlet UIImageView* _Nullable userImage;
@property (nonatomic, weak) IBOutlet UIButton* _Nullable badge;
@property (nonatomic, weak) IBOutlet UIImageView* _Nullable muteBadge;
@property (nonatomic, weak) IBOutlet UIImageView* _Nullable mentionBadge;
@property (weak, nonatomic) IBOutlet UIImageView* _Nullable pinBadge;

//isaCloud: a chat with a red unread counter (notification or mention) shows its preview in bold and near black
@property (nonatomic) BOOL previewHighlighted;
+(UIColor* _Nonnull) previewHighlightColor;

@property (nonatomic, assign) BOOL isPinned;

-(void) initCell:(MLContact* _Nonnull) contact withLastMessage:(MLMessage* _Nullable) lastMessage;
//isaCloud: with more than one account, the account's jid under the name (nil hides the line)
-(void) showAccountJid:(NSString* _Nullable) accountJid;

@end
