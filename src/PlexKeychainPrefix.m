// Plex's keychain group follows whoever signed the app.
//
// Plex keeps its sign-in token in a keychain access group named from the
// PlexAppIdPrefix value in Info.plist ("<team ID>."). A sideloaded copy is
// signed by the person installing it, so that value must be their team ID or
// every keychain write fails and Plex reports "Login Credentials Expired".
// Release IPAs cannot know the signer's team, so at launch the add-on reads the
// team from the app's own default keychain group (stored with every item it
// adds) and answers Plex's Info.plist lookups with it.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>

static NSString *PLXSignedPrefix;

// "<team ID>." for the team that signed this copy, or nil when it cannot be read.
static NSString *PLXReadSignedPrefix(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"PlexReborn.teamProbe",
        (__bridge id)kSecAttrAccount: @"teamProbe",
        (__bridge id)kSecReturnAttributes: @YES,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *add = [query mutableCopy];
        add[(__bridge id)kSecValueData] = [NSData data];
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        status = SecItemAdd((__bridge CFDictionaryRef)add, &result);
    }
    if (status != errSecSuccess || !result) return nil;
    NSDictionary *attributes = (__bridge_transfer NSDictionary *)result;
    NSString *group = attributes[(__bridge id)kSecAttrAccessGroup];
    NSRange dot = [group rangeOfString:@"."];
    if (dot.location != 10) return nil; // team IDs are 10 characters
    return [group substringToIndex:dot.location + 1];
}

static IMP PLXOrigObjectForInfoKey, PLXOrigInfoDictionary;

static id PLXObjectForInfoKey(NSBundle *self, SEL _cmd, NSString *key) {
    if (PLXSignedPrefix && self == NSBundle.mainBundle && [key isEqualToString:@"PlexAppIdPrefix"]) return PLXSignedPrefix;
    return ((id (*)(id, SEL, id))PLXOrigObjectForInfoKey)(self, _cmd, key);
}

static NSDictionary *PLXInfoDictionary(NSBundle *self, SEL _cmd) {
    NSDictionary *info = ((id (*)(id, SEL))PLXOrigInfoDictionary)(self, _cmd);
    if (!PLXSignedPrefix || self != NSBundle.mainBundle || [info[@"PlexAppIdPrefix"] isEqual:PLXSignedPrefix]) return info;
    static NSDictionary *patched;
    if (!patched) {
        NSMutableDictionary *copy = [info mutableCopy];
        copy[@"PlexAppIdPrefix"] = PLXSignedPrefix;
        patched = [copy copy];
    }
    return patched;
}

__attribute__((constructor)) static void PLXInstallKeychainPrefix(void) {
    NSString *prefix = PLXReadSignedPrefix();
    NSString *declared = [NSBundle.mainBundle objectForInfoDictionaryKey:@"PlexAppIdPrefix"];
    if (!prefix || [prefix isEqualToString:declared]) return;
    PLXSignedPrefix = prefix;
    Class bundle = NSBundle.class;
    PLXOrigObjectForInfoKey = method_setImplementation(class_getInstanceMethod(bundle, @selector(objectForInfoDictionaryKey:)), (IMP)PLXObjectForInfoKey);
    PLXOrigInfoDictionary = method_setImplementation(class_getInstanceMethod(bundle, @selector(infoDictionary)), (IMP)PLXInfoDictionary);
}
