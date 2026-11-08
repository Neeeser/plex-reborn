// Simulator-only stand-in for the keychain.
//
// The converted simulator copy is ad-hoc signed, has no application-identifier,
// and the simulator refuses to launch it with keychain entitlements added, so
// every SecItem call fails with errSecMissingEntitlement (-34018). Plex then
// cannot keep its sign-in token and reports "Login Credentials Expired".
// These interposers keep items in a plist inside the app's Library folder,
// which is enough for Plex's token storage during simulator testing. Device
// builds never include this file and use the real keychain.
#import <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSString *PLXStorePath(void) {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [library stringByAppendingPathComponent:@"PlexSimKeychain.plist"];
}

static NSMutableArray<NSMutableDictionary *> *PLXItems(void) {
    static NSMutableArray *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *saved = [NSArray arrayWithContentsOfFile:PLXStorePath()];
        items = [NSMutableArray array];
        for (NSDictionary *item in saved) [items addObject:[item mutableCopy]];
    });
    return items;
}

static void PLXSave(void) {
    [PLXItems() writeToFile:PLXStorePath() atomically:YES];
}

// Keys that identify an item. Everything else in a query is a search option
// (return type, match limit) or an attribute Plex does not filter on.
static NSArray<NSString *> *PLXIdentityKeys(void) {
    return @[ (__bridge NSString *)kSecClass, (__bridge NSString *)kSecAttrService,
              (__bridge NSString *)kSecAttrAccount, (__bridge NSString *)kSecAttrGeneric,
              (__bridge NSString *)kSecAttrServer, (__bridge NSString *)kSecAttrLabel ];
}

static BOOL PLXMatches(NSDictionary *item, NSDictionary *query) {
    for (NSString *key in PLXIdentityKeys()) {
        id wanted = query[key];
        if (wanted && ![wanted isEqual:item[key]]) return NO;
    }
    return YES;
}

static NSDictionary *PLXStoredAttributes(NSDictionary *source) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    for (NSString *key in source) {
        id value = source[key];
        // Keep plist-safe attribute values; drop search options and references.
        if ([key hasPrefix:@"r_"] || [key hasPrefix:@"m_"] || [key isEqualToString:(__bridge NSString *)kSecAttrAccessGroup]) continue;
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSData class]] ||
            [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDate class]]) {
            attributes[key] = value;
        }
    }
    return attributes;
}

static id PLXResultFor(NSDictionary *item, NSDictionary *query) {
    BOOL wantData = [query[(__bridge NSString *)kSecReturnData] boolValue];
    BOOL wantAttributes = [query[(__bridge NSString *)kSecReturnAttributes] boolValue];
    BOOL wantPersistent = [query[(__bridge NSString *)kSecReturnPersistentRef] boolValue];
    if (wantAttributes || wantPersistent) {
        NSMutableDictionary *result = [item mutableCopy];
        if (!wantData) [result removeObjectForKey:(__bridge NSString *)kSecValueData];
        if (wantPersistent) result[(__bridge NSString *)kSecValuePersistentRef] = [@(item.hash).stringValue dataUsingEncoding:NSUTF8StringEncoding];
        return result;
    }
    if (wantData) return item[(__bridge NSString *)kSecValueData];
    return nil;
}

static OSStatus PLXSecItemAdd(CFDictionaryRef cfAttributes, CFTypeRef *result) {
    @synchronized (PLXItems()) {
        NSDictionary *attributes = (__bridge NSDictionary *)cfAttributes;
        for (NSDictionary *item in PLXItems()) {
            if (PLXMatches(item, attributes)) return errSecDuplicateItem;
        }
        NSMutableDictionary *item = [PLXStoredAttributes(attributes) mutableCopy];
        [PLXItems() addObject:item];
        PLXSave();
        if (result) {
            id value = PLXResultFor(item, attributes);
            *result = value ? CFBridgingRetain(value) : NULL;
        }
        return errSecSuccess;
    }
}

static OSStatus PLXSecItemCopyMatching(CFDictionaryRef cfQuery, CFTypeRef *result) {
    @synchronized (PLXItems()) {
        NSDictionary *query = (__bridge NSDictionary *)cfQuery;
        BOOL all = [query[(__bridge NSString *)kSecMatchLimit] isEqual:(__bridge NSString *)kSecMatchLimitAll];
        NSMutableArray *found = [NSMutableArray array];
        for (NSDictionary *item in PLXItems()) {
            if (!PLXMatches(item, query)) continue;
            id value = PLXResultFor(item, query);
            if (value) [found addObject:value];
            else [found addObject:@{}];
            if (!all) break;
        }
        if (found.count == 0) return errSecItemNotFound;
        if (result) {
            id value = all ? found : found.firstObject;
            *result = ([value isKindOfClass:[NSDictionary class]] && [value count] == 0) ? NULL : CFBridgingRetain(value);
        }
        return errSecSuccess;
    }
}

static OSStatus PLXSecItemUpdate(CFDictionaryRef cfQuery, CFDictionaryRef cfChanges) {
    @synchronized (PLXItems()) {
        NSDictionary *query = (__bridge NSDictionary *)cfQuery;
        NSDictionary *changes = PLXStoredAttributes((__bridge NSDictionary *)cfChanges);
        BOOL updated = NO;
        for (NSMutableDictionary *item in PLXItems()) {
            if (!PLXMatches(item, query)) continue;
            [item addEntriesFromDictionary:changes];
            updated = YES;
        }
        if (!updated) return errSecItemNotFound;
        PLXSave();
        return errSecSuccess;
    }
}

static OSStatus PLXSecItemDelete(CFDictionaryRef cfQuery) {
    @synchronized (PLXItems()) {
        NSDictionary *query = (__bridge NSDictionary *)cfQuery;
        NSIndexSet *matches = [PLXItems() indexesOfObjectsPassingTest:^BOOL(NSMutableDictionary *item, NSUInteger index, BOOL *stop) {
            return PLXMatches(item, query);
        }];
        if (matches.count == 0) return errSecItemNotFound;
        [PLXItems() removeObjectsAtIndexes:matches];
        PLXSave();
        return errSecSuccess;
    }
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } PLXKeychainInterposers[] = {
    { (const void *)PLXSecItemAdd, (const void *)SecItemAdd },
    { (const void *)PLXSecItemCopyMatching, (const void *)SecItemCopyMatching },
    { (const void *)PLXSecItemUpdate, (const void *)SecItemUpdate },
    { (const void *)PLXSecItemDelete, (const void *)SecItemDelete },
};
#endif
