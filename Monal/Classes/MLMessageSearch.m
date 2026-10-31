//
//  MLMessageSearch.m
//  monalxmpp
//
//  isaCloud: full text search in the messages, see MLMessageSearch.h
//
//  Copyright © 2026 isaCloud. All rights reserved.
//

#import <monalxmpp/MLMessageSearch.h>
#import <sqlite3.h>
#import <monalxmpp/MLSQLite.h>
#import <monalxmpp/HelperTools.h>

//what can be found: the text of a message (or a message that is only a link), not retracted. Files are left out because the address of an encrypted
//file carries its OMEMO key (aesgcm://...#key), and the "message" of a retracted message is empty.
//(the prefix is the table name with a dot where the query also has the search table, whose column is called "message" too)
#define SEARCHABLE_CONDITION(prefix) @prefix "messageType IN ('Text', 'Url') AND IFNULL(" prefix "retracted, 0) = 0 AND " prefix "message != ''"

//the table is "contentless" (it stores no copy of the text, only the words) and supports DELETE by rowid; the rowid is the message_history_id
#define kCreateSearchTable @"CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5(message, content='', contentless_delete=1, tokenize='unicode61 remove_diacritics 2');"

//message_history_ids are not only growing: messages loaded backwards from the server archive get decreasing (negative) ids.
//So "what was not indexed yet" is everything above the highest id we indexed or below the lowest one.
#define kFlagMaxId @"isacloud_search_max_id"
#define kFlagMinId @"isacloud_search_min_id"
#define kFlagPurgedAt @"isacloud_search_purged_at"

static const NSTimeInterval kPurgeInterval = 24 * 60 * 60;

@implementation MLMessageSearch

+(BOOL) isAvailable
{
    //the compile options of the SQLite this build was linked with (the same strings the build check looks for in the binary)
    return sqlite3_compileoption_used("ENABLE_FTS5") != 0;
}

+(NSString* _Nullable) matchStringForQuery:(NSString*) query
{
    if(query == nil)
        return nil;
    NSMutableArray<NSString*>* words = [NSMutableArray new];
    NSCharacterSet* alphanumerics = [NSCharacterSet alphanumericCharacterSet];
    for(NSString* word in [query componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])
    {
        //a word without any letter or digit has no token in the index (an empty phrase is a syntax error for FTS5)
        if([word rangeOfCharacterFromSet:alphanumerics].location == NSNotFound)
            continue;
        //a phrase in double quotes cannot contain FTS5 syntax (AND, OR, NOT, *, :, ...), a double quote inside is written twice;
        //the star after the closing quote makes it a prefix
        NSString* escaped = [word stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
        [words addObject:[NSString stringWithFormat:@"\"%@\"*", escaped]];
    }
    if(words.count == 0)
        return nil;
    return [words componentsJoinedByString:@" "];
}

+(void) fillIndexInDatabase:(MLSQLite*) db where:(NSString*) condition arguments:(NSArray*) arguments
{
    //first forget what the index may hold for these rows (rows can be indexed already by the hooks), then index them again
    [db executeNonQuery:[NSString stringWithFormat:@"DELETE FROM message_search WHERE rowid IN (SELECT message_history_id FROM message_history WHERE %@);", condition] andArguments:arguments];
    [db executeNonQuery:[NSString stringWithFormat:@"INSERT INTO message_search(rowid, message) SELECT message_history_id, message FROM message_history WHERE (%@) AND %@;", condition, SEARCHABLE_CONDITION("")] andArguments:arguments];
}

+(void) createIndexInDatabase:(MLSQLite*) db
{
    //creating the table is part of the catch up, which never throws: whatever goes wrong with the index, the app still starts,
    //and the next start tries again
    [self catchUpIndexInDatabase:db];
}

+(void) catchUpIndexInDatabase:(MLSQLite*) db
{
    if(![self isAvailable])
    {
        //a build without FTS5 (stale compiled SQLite): leave the database as it is, a build that has it will create and fill the index
        DDLogError(@"Search index: FTS5 MISSING in the SQLite of this build, the message search is off (see docs/troubleshooting.md)");
        return;
    }
    @try {
        [db executeNonQuery:kCreateSearchTable];

        NSNumber* maxIndexed = (NSNumber*)[db executeScalar:[NSString stringWithFormat:@"SELECT value FROM flags WHERE name='%@';", kFlagMaxId]];
        NSNumber* minIndexed = (NSNumber*)[db executeScalar:[NSString stringWithFormat:@"SELECT value FROM flags WHERE name='%@';", kFlagMinId]];
        NSNumber* currentMax = (NSNumber*)[db executeScalar:@"SELECT MAX(message_history_id) FROM message_history;"];
        NSNumber* currentMin = (NSNumber*)[db executeScalar:@"SELECT MIN(message_history_id) FROM message_history;"];
        if(currentMax == nil || currentMin == nil || [currentMax isKindOfClass:[NSNull class]])
        {
            //no messages at all
            return;
        }

        if(maxIndexed == nil || minIndexed == nil)
        {
            //the index was never filled: index everything
            DDLogInfo(@"Search index: indexing all messages...");
            [self fillIndexInDatabase:db where:@"1=1" arguments:@[]];
        }
        else
        {
            if(currentMax.longLongValue > maxIndexed.longLongValue)
            {
                DDLogInfo(@"Search index: indexing messages above id %@", maxIndexed);
                [self fillIndexInDatabase:db where:@"message_history_id > ?" arguments:@[maxIndexed]];
            }
            if(currentMin.longLongValue < minIndexed.longLongValue)
            {
                DDLogInfo(@"Search index: indexing messages below id %@", minIndexed);
                [self fillIndexInDatabase:db where:@"message_history_id < ?" arguments:@[minIndexed]];
            }
        }
        [db executeNonQuery:@"INSERT OR REPLACE INTO flags (name, value) VALUES(?, ?);" andArguments:@[kFlagMaxId, currentMax]];
        [db executeNonQuery:@"INSERT OR REPLACE INTO flags (name, value) VALUES(?, ?);" andArguments:@[kFlagMinId, currentMin]];

        //messages that were deleted without the hooks hearing about it (a contact removed, the foreign keys of the database): forget their words,
        //so the index does not keep the words of messages that are gone (the search never shows them, it checks every result)
        NSNumber* purgedAt = (NSNumber*)[db executeScalar:[NSString stringWithFormat:@"SELECT value FROM flags WHERE name='%@';", kFlagPurgedAt]];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if(purgedAt == nil || now - purgedAt.doubleValue > kPurgeInterval)
        {
            [db executeNonQuery:@"DELETE FROM message_search WHERE rowid IN (SELECT rowid FROM message_search WHERE rowid NOT IN (SELECT message_history_id FROM message_history));"];
            [db executeNonQuery:@"INSERT OR REPLACE INTO flags (name, value) VALUES(?, ?);" andArguments:@[kFlagPurgedAt, @(now)]];
        }
    } @catch(NSException* exception) {
        //the search is a convenience: never let it keep the app from starting
        DDLogError(@"Search index: could not be brought up to date: %@", exception);
    }
}

+(void) updateIndexForHistoryId:(NSNumber* _Nullable) historyId inDatabase:(MLSQLite*) db
{
    if(historyId == nil)
        return;
    @try {
        [db executeNonQuery:@"DELETE FROM message_search WHERE rowid=?;" andArguments:@[historyId]];
        [db executeNonQuery:[NSString stringWithFormat:@"INSERT INTO message_search(rowid, message) SELECT message_history_id, message FROM message_history WHERE message_history_id=? AND %@;", SEARCHABLE_CONDITION("")] andArguments:@[historyId]];
    } @catch(NSException* exception) {
        DDLogError(@"Search index: could not update the entry of message %@: %@", historyId, exception);
    }
}

+(void) indexNewMessageWithHistoryId:(NSNumber* _Nullable) historyId inDatabase:(MLSQLite*) db
{
    if(historyId == nil)
        return;
    @try {
        [db executeNonQuery:[NSString stringWithFormat:@"INSERT INTO message_search(rowid, message) SELECT message_history_id, message FROM message_history WHERE message_history_id=? AND %@;", SEARCHABLE_CONDITION("")] andArguments:@[historyId]];
    } @catch(NSException* exception) {
        DDLogError(@"Search index: could not index the new message %@: %@", historyId, exception);
    }
}

+(void) removeFromIndexMessagesWhere:(NSString*) condition arguments:(NSArray*) arguments inDatabase:(MLSQLite*) db
{
    @try {
        [db executeNonQuery:[NSString stringWithFormat:@"DELETE FROM message_search WHERE rowid IN (SELECT message_history_id FROM message_history WHERE %@);", condition] andArguments:arguments];
    } @catch(NSException* exception) {
        DDLogError(@"Search index: could not remove entries (%@): %@", condition, exception);
    }
}

+(NSArray<NSNumber*>*) historyIdsMatchingQuery:(NSString*) query limit:(NSUInteger) limit offset:(NSUInteger) offset inDatabase:(MLSQLite*) db
{
    NSString* match = [self matchStringForQuery:query];
    if(match == nil)
        return @[];
    //every result is read from message_history again: the index only says which messages to look at
    NSString* sql = [NSString stringWithFormat:@"SELECT message_history.message_history_id FROM message_search \
        JOIN message_history ON message_history.message_history_id = message_search.rowid \
        JOIN account ON account.account_id = message_history.account_id \
        WHERE message_search MATCH ? AND account.enabled = 1 AND %@ \
        ORDER BY message_history.timestamp DESC, message_history.message_history_id DESC LIMIT ? OFFSET ?;",
        SEARCHABLE_CONDITION("message_history.")
    ];
    @try {
        NSArray* result = [db executeScalarReader:sql andArguments:@[match, @(limit), @(offset)]];
        return result != nil ? result : @[];
    } @catch(NSException* exception) {
        //a search that fails is an empty search, never a crash
        DDLogError(@"Search: query '%@' failed: %@", query, exception);
        return @[];
    }
}

@end
