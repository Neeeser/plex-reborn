// Simulator-only: report the simulated iPhone's model identifier.
//
// Plex reads hw.machine / uname() and splits it on "," (expecting "iPhone19,4").
// In the simulator these return the Mac's "arm64", so Plex indexes past the end
// of the split array and crashes at launch. The simulator publishes the real
// identifier in SIMULATOR_MODEL_IDENTIFIER, which these interposers return.
#include <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

static const char *PLXSimModel(void) {
    const char *model = getenv("SIMULATOR_MODEL_IDENTIFIER");
    return (model && *model) ? model : "iPhone19,4";
}

static int PLXSysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0) && oldlenp) {
        const char *model = PLXSimModel();
        size_t needed = strlen(model) + 1;
        if (oldp) {
            if (*oldlenp < needed) { *oldlenp = needed; return -1; }
            memcpy(oldp, model, needed);
        }
        *oldlenp = needed;
        return 0;
    }
    return sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int PLXUname(struct utsname *info) {
    int result = uname(info);
    if (result == 0 && info) {
        strlcpy(info->machine, PLXSimModel(), sizeof(info->machine));
    }
    return result;
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } PLXInterposers[] = {
    { (const void *)PLXSysctlbyname, (const void *)sysctlbyname },
    { (const void *)PLXUname, (const void *)uname },
};
#endif
