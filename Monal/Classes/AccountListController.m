//
//  AccountListController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "AccountListController.h"
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLImageManager.h>
#import <monalxmpp/MLContact.h>
#import "GeneratedAssetSymbols.h"
#import "ActiveChatsViewController.h"

@interface AccountListController ()
@property (nonatomic, strong) NSDateFormatter* uptimeFormatter;

@property (nonatomic, strong) NSIndexPath* selected; // User-selected account - needed for segue
@property (nonatomic, strong) UITableView* accountsTable;
@property (nonatomic, strong) NSArray<NSDictionary*>* accountList;

@end

@implementation AccountListController


#pragma mark View life cycle
- (void) setupAccountsView
{
	// Do any additional setup after loading the view.
    self.accountsTable.backgroundView = nil;
    self.accountsTable = self.tableView;
    self.accountsTable.delegate = self;
    self.accountsTable.dataSource = self;
 
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.accountsTable reloadData];
    });
    
    self.uptimeFormatter = [NSDateFormatter new];
    self.uptimeFormatter.dateStyle = NSDateFormatterShortStyle;
    self.uptimeFormatter.timeStyle = NSDateFormatterShortStyle;
    self.uptimeFormatter.doesRelativeDateFormatting = YES;
    self.uptimeFormatter.locale = [NSLocale currentLocale];
    self.uptimeFormatter.timeZone = [NSTimeZone systemTimeZone];

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refreshAccountList) name:kMonalAccountStatusChanged object:nil];
    [nc addObserver:self selector:@selector(refreshAccountList) name:kMonalRefresh object:nil];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(NSUInteger) getAccountNum
{
    return self.accountList.count;
}

-(NSNumber*) getAccountIDByIndex:(NSUInteger) index
{
    NSNumber* result = [[self.accountList objectAtIndex: index] objectForKey:@"account_id"];
    MLAssert(result != nil, @"getAccountIDByIndex, result should not be nil");
    return result;
}

-(void) refreshAccountList
{
    NSArray* accountList = [[DataLayer sharedInstance] accountList];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.accountList = accountList;
        [self.accountsTable reloadData];
    });
}

-(void) initContactCell:(MLSwitchCell*) cell forAccNo:(NSUInteger) accNo
{
    [cell initTapCell:@"\n\n"];
    NSDictionary* account = [self.accountList objectAtIndex:accNo];
    MLAssert(account != nil, ([NSString stringWithFormat:@"Expected non nil account in row %lu", (unsigned long)accNo]));
    if([(NSString*)[account objectForKey:@"domain"] length] > 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"%@@%@", [[self.accountList objectAtIndex:accNo] objectForKey:@"username"],
                                [[self.accountList objectAtIndex:accNo] objectForKey:@"domain"]];
    }
    else
    {
        cell.textLabel.text = [[self.accountList objectAtIndex:accNo] objectForKey:@"username"];
    }

    UIImageView* accessory = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];

    //isaCloud: the avatar of the account instead of the check mark: a disabled account has a faded avatar with a "paused" mark
    //(the check mark used to tell enabled from disabled)
    UIImage* accountAvatar = [[MLImageManager sharedInstance] getIconForContact:[MLContact createContactFromJid:[NSString stringWithFormat:@"%@@%@", account[@"username"], account[@"domain"]] andAccountID:account[@"account_id"]]];
    if(accountAvatar == nil)
        accountAvatar = [UIImage imageNamed:ACImageNameNoicon];
    cell.imageView.image = [[HelperTools roundAvatar:accountAvatar diameter:38 disabled:![[account objectForKey:@"enabled"] boolValue]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];

    if([[account objectForKey:@"enabled"] boolValue] == YES)
    {
        if([[MLXMPPManager sharedInstance] isAccountForIdConnected:[[self.accountList objectAtIndex:accNo] objectForKey:@"account_id"]])
        {
            accessory.image = [UIImage imageNamed:ACImageNameConnected];
            accessory.contentMode = UIViewContentModeScaleAspectFit;
            cell.accessoryView = [self accessoryWithVisibilityButtonFor:accessory forAccount:account];
        }
        else
        {
            //isaCloud: enabled but not connected means Monal is trying to (re)connect: show a warning symbol instead of the grey dot
            UIImageSymbolConfiguration* symbolConfig = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
            accessory.image = [[UIImage systemImageNamed:@"exclamationmark.arrow.triangle.2.circlepath" withConfiguration:symbolConfig] imageWithTintColor:[UIColor systemOrangeColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
            accessory.contentMode = UIViewContentModeCenter;
            accessory.isAccessibilityElement = YES;
            accessory.accessibilityLabel = NSLocalizedString(@"Reconnecting...", @"");
            cell.accessoryView = [self accessoryWithVisibilityButtonFor:accessory forAccount:account];
        }
    }
    else
    {
        accessory.image = nil;
        cell.accessoryView = accessory;
    }
}

//isaCloud: eye button before the status mark of an enabled account: hides or shows the chats of the account in the chat list
//(only in memory, see ActiveChatsViewController.h)
-(UIView*) accessoryWithVisibilityButtonFor:(UIView*) statusView forAccount:(NSDictionary*) account
{
    BOOL hidden = [ActiveChatsViewController isChatListAccountHidden:account[@"account_id"]];
    
    //the eye keeps its own proportions (a button configuration lays the symbol out at its natural size, a plain button image was
    //being stretched into the square frame) and the status mark sits in a smaller square, vertically centered
    UIView* container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];

    UIButtonConfiguration* buttonConfig = [UIButtonConfiguration plainButtonConfiguration];
    buttonConfig.image = [UIImage systemImageNamed:(hidden ? @"eye.slash" : @"eye")];
    buttonConfig.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular];
    buttonConfig.contentInsets = NSDirectionalEdgeInsetsZero;
    buttonConfig.baseForegroundColor = [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor lightGrayColor] : [UIColor darkGrayColor];
    }];
    UIButton* button = [UIButton buttonWithConfiguration:buttonConfig primaryAction:nil];
    button.frame = CGRectMake(0, 0, 34, 30);
    button.tag = [account[@"account_id"] integerValue];
    button.accessibilityLabel = hidden ? NSLocalizedString(@"Show this account's chats", @"") : NSLocalizedString(@"Hide this account's chats", @"");
    [button addTarget:self action:@selector(toggleAccountVisibility:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:button];
    
    statusView.frame = CGRectMake(40, 5, 20, 20);
    [container addSubview:statusView];
    
    return container;
}

-(void) toggleAccountVisibility:(UIButton*) sender
{
    NSNumber* accountID = [NSNumber numberWithInteger:sender.tag];
    BOOL hidden = [ActiveChatsViewController isChatListAccountHidden:accountID];
    [ActiveChatsViewController setChatListAccount:accountID hidden:!hidden];
    [self.accountsTable reloadData];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalRefresh object:self userInfo:nil];
}

@end
