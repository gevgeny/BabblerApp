#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "default" asset catalog image resource.
static NSString * const ACImageNameDefault AC_SWIFT_PRIVATE = @"default";

/// The "default_warn" asset catalog image resource.
static NSString * const ACImageNameDefaultWarn AC_SWIFT_PRIVATE = @"default_warn";

#undef AC_SWIFT_PRIVATE
