/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import "KeyboardManager.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#if defined(__linux__)
#include <dirent.h>
#endif
#if !defined(__linux__)
#include <login_cap.h>
#if defined(__OpenBSD__)
#define GW_LOGIN_GETPWCLASS(p) login_getclass((p)->pw_class)
#else
#define GW_LOGIN_GETPWCLASS(p) login_getpwclass(p)
#endif
#endif
static const char *rpiKeyboardLayout(int idx)
{
    static const char *table[15] = {
        "gb", "gb", "fr", "es", "us", "de", "it",
        "jp", "pt", "no", "se", "dk", "ru", "tr", "il"
    };
    if (idx < 0 || idx > 14) return "gb";
    return table[idx];
}
static const char *rpiKeyboardVIDs[] = { "04d9", "2e8a", NULL };
static const char *rpiKeyboardPIDs[] = { "0006", "0010", NULL };
static BOOL detectKeyboardFromUSB(const char **layout,
                                  const char **variant,
                                  const char **options)
{
#if defined(__linux__)
    DIR *usb_dir = opendir("/sys/bus/usb/devices");
    if (!usb_dir) return NO;
    struct dirent *entry;
    while ((entry = readdir(usb_dir)) != NULL) {
        if (entry->d_name[0] == '.') continue;
        char path[512];
        char vendor[16] = "", id_product[16] = "", prod_str[256] = "";
        snprintf(path, sizeof(path), "/sys/bus/usb/devices/%s/idVendor",
                 entry->d_name);
        FILE *f = fopen(path, "r");
        if (!f) continue;
        if (!fgets(vendor, sizeof(vendor), f)) { fclose(f); continue; }
        fclose(f);
        vendor[strcspn(vendor, "\n")] = '\0';
        snprintf(path, sizeof(path), "/sys/bus/usb/devices/%s/idProduct",
                 entry->d_name);
        f = fopen(path, "r");
        if (!f) continue;
        if (!fgets(id_product, sizeof(id_product), f)) { fclose(f); continue; }
        fclose(f);
        id_product[strcspn(id_product, "\n")] = '\0';
        BOOL known = NO;
        for (int i = 0; rpiKeyboardVIDs[i] && rpiKeyboardPIDs[i]; i++) {
            if (strcmp(vendor, rpiKeyboardVIDs[i]) == 0
                && strcmp(id_product, rpiKeyboardPIDs[i]) == 0) {
                known = YES;
                break;
            }
        }
        if (!known) continue;
        snprintf(path, sizeof(path), "/sys/bus/usb/devices/%s/product",
                 entry->d_name);
        f = fopen(path, "r");
        if (!f) continue;
        if (!fgets(prod_str, sizeof(prod_str), f)) { fclose(f); continue; }
        fclose(f);
        prod_str[strcspn(prod_str, "\n")] = '\0';
        BOOL is_rpi = (strstr(prod_str, "RPI") != NULL
                       || strstr(prod_str, "Raspberry") != NULL
                       || strstr(prod_str, "raspberry") != NULL
                       || strstr(prod_str, "Pi ") != NULL);
        if (!is_rpi) {
            NSLog(@"KeyboardManager: USB %s:%s product '%s' not an RPI keyboard, skipping",
                  vendor, id_product, prod_str);
            continue;
        }
        const char *last_space = strrchr(prod_str, ' ');
        int idx = 0;
        if (last_space) {
            const char *tok = last_space + 1;
            if (*tok < '0' || *tok > '9') {
                NSLog(@"KeyboardManager: USB %s:%s product '%s' has no trailing index, deferring",
                      vendor, id_product, prod_str);
                continue;
            }
            idx = atoi(tok);
        }
        if (idx < 0 || idx > 14) idx = 0;
        *layout = rpiKeyboardLayout(idx);
        *variant = "";
        *options = "";
        NSLog(@"KeyboardManager: RPI USB keyboard index %d -> layout '%s'",
              idx, *layout);
        closedir(usb_dir);
        return YES;
    }
    closedir(usb_dir);
#else
    (void)layout;
    (void)variant;
    (void)options;
#endif
    return NO;
}
static BOOL detectKeyboardFromDeviceTree(const char **layout,
                                         const char **variant,
                                         const char **options)
{
#if defined(__linux__)
    FILE *f = fopen("/proc/device-tree/chosen/rpi-country-code", "rb");
    if (!f) return NO;
    unsigned char buf[4];
    size_t n = fread(buf, 1, sizeof(buf), f);
    fclose(f);
    if (n != 4) return NO;
    int idx = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
    if (idx < 0 || idx > 14) idx = 0;
    *layout = rpiKeyboardLayout(idx);
    *variant = "";
    *options = "";
    NSLog(@"KeyboardManager: RPI device-tree country-code %d -> layout '%s'",
          idx, *layout);
    return YES;
#else
    (void)layout;
    (void)variant;
    (void)options;
    return NO;
#endif
}
static void writeFileIfAbsent(const char *path, const char *content)
{
    if (access(path, F_OK) == 0) {
        NSLog(@"KeyboardManager: Config file %s already exists, not overwriting", path);
        return;
    }
    FILE *fp = fopen(path, "w");
    if (fp) {
        fputs(content, fp);
        fclose(fp);
        NSLog(@"KeyboardManager: Created config file %s", path);
    } else {
        NSLog(@"KeyboardManager: ERROR: Could not create %s: %s", path, strerror(errno));
    }
}
static void writeKeyboardConfigFile(const char *layout,
                                    const char *variant,
                                    const char *options)
{
    const char *kb = layout ? layout : "us";
    const char *vr = variant ? variant : "";
    const char *op = options ? options : "";
#if defined(__linux__)
    char buf[4096];
    int n;
    n = snprintf(buf, sizeof(buf),
        "XKBMODEL=\"pc105\"\n"
        "XKBLAYOUT=\"%s\"\n"
        "XKBVARIANT=\"%s\"\n"
        "XKBOPTIONS=\"%s\"\n",
        kb, vr, op);
    if (n > 0 && n < (int)sizeof(buf))
        writeFileIfAbsent("/etc/default/keyboard", buf);
    if (vr[0])
        n = snprintf(buf, sizeof(buf),
            "KEYMAP=\"%s\"\n"
            "XKBLAYOUT=\"%s\"\n"
            "XKBVARIANT=\"%s\"\n",
            kb, kb, vr);
    else
        n = snprintf(buf, sizeof(buf),
            "KEYMAP=\"%s\"\n",
            kb);
    if (n > 0 && n < (int)sizeof(buf))
        writeFileIfAbsent("/etc/vconsole.conf", buf);
#elif defined(__FreeBSD__)
    char buf[1024];
    int n = snprintf(buf, sizeof(buf),
        "keymap=\"%s.kbd\"\n",
        kb);
    if (n > 0 && n < (int)sizeof(buf))
        writeFileIfAbsent("/etc/rc.conf.d/keyboard", buf);
#elif defined(__OpenBSD__)
    char buf[256];
    int n = snprintf(buf, sizeof(buf), "%s\n", kb);
    if (n > 0 && n < (int)sizeof(buf))
        writeFileIfAbsent("/etc/kbdtype", buf);
#elif defined(__NetBSD__)
    if (access("/etc/wscons.conf", F_OK) != 0) {
        char buf[512];
        int n = snprintf(buf, sizeof(buf),
            "encoding %s\n",
            kb);
        if (n > 0 && n < (int)sizeof(buf))
            writeFileIfAbsent("/etc/wscons.conf", buf);
    } else {
        NSLog(@"KeyboardManager: /etc/wscons.conf already exists, not overwriting");
    }
#endif
    (void)op;
}
static const char *findSetxkbmap(void)
{
    static const char *paths[] = {
        "/usr/local/bin/setxkbmap",
        "/usr/bin/setxkbmap",
        "/bin/setxkbmap",
        "/usr/X11R6/bin/setxkbmap",
        "/usr/X11R7/bin/setxkbmap",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        if (access(paths[i], X_OK) == 0)
            return paths[i];
    }
    return NULL;
}
static BOOL applyKeyboardToXServer(const char *layout,
                                   const char *variant,
                                   const char *options)
{
    const char *setxkbmap = findSetxkbmap();
    if (!setxkbmap) {
        NSLog(@"KeyboardManager: ERROR: setxkbmap not found in any standard path");
        return NO;
    }
    char xkb_cmd[512];
    int n = snprintf(xkb_cmd, sizeof(xkb_cmd),
                     "%s -option '' 2>/dev/null;"
                     "%s %s%s%s%s%s%s 2>/dev/null",
                     setxkbmap, setxkbmap,
                     layout ? layout : "us",
                     (variant && variant[0]) ? " -variant " : "",
                     (variant && variant[0]) ? variant : "",
                     (options && options[0]) ? " -option " : "",
                     (options && options[0]) ? options : "",
                     "");
    if (n <= 0 || n >= (int)sizeof(xkb_cmd)) return NO;
    int rc = system(xkb_cmd);
    if (rc != 0)
        NSLog(@"KeyboardManager: WARNING: setxkbmap exited with status %d", rc);
    return (rc == 0);
}
static BOOL parseRcConfKeymap(const char **layout, const char **variant)
{
    FILE *rc_conf = fopen("/etc/rc.conf", "r");
    if (!rc_conf) return NO;
    char line[256];
    BOOL found = NO;
    while (fgets(line, sizeof(line), rc_conf)) {
        if (strncmp(line, "keymap=", 7) != 0) continue;
        char *keymap = strchr(line, '=') + 1;
        char *nl = strchr(keymap, '\n');
        if (nl) *nl = '\0';
        if (keymap[0] == '"') {
            keymap++;
            char *eq = strchr(keymap, '"');
            if (eq) *eq = '\0';
        }
        NSLog(@"KeyboardManager: /etc/rc.conf keymap: %s", keymap);
        if (strstr(keymap, "us"))       *layout = "us";
        else if (strstr(keymap, "de"))  *layout = "de";
        else if (strstr(keymap, "fr"))  *layout = "fr";
        else if (strstr(keymap, "es"))  *layout = "es";
        else if (strstr(keymap, "it"))  *layout = "it";
        else if (strstr(keymap, "pt"))  *layout = "pt";
        else if (strstr(keymap, "ru"))  *layout = "ru";
        else if (strstr(keymap, "uk") || strstr(keymap, "gb")) *layout = "gb";
        else if (strstr(keymap, "dvorak")) {
            *layout = "us";
            *variant = "dvorak";
        } else {
            *layout = "us";
            NSLog(@"KeyboardManager: Unknown keymap '%s', using 'us'", keymap);
        }
        found = YES;
        break;
    }
    fclose(rc_conf);
    return found;
}
static BOOL parseEtcDefaultKeyboard(const char **layout,
                                    const char **variant,
                                    const char **options)
{
#if defined(__linux__)
    static char buf_layout[64], buf_variant[64], buf_options[256];
    FILE *fp = fopen("/etc/default/keyboard", "r");
    if (!fp) return NO;
    char line[256];
    BOOL found = NO;
    while (fgets(line, sizeof(line), fp)) {
        char *nl = strchr(line, '\n');
        if (nl) *nl = '\0';
        if (strncmp(line, "XKBLAYOUT=", 10) == 0) {
            char *val = line + 10;
            if (*val == '"') { val++; char *eq = strchr(val, '"'); if (eq) *eq = '\0'; }
            if (val[0]) { strncpy(buf_layout, val, sizeof(buf_layout) - 1); buf_layout[sizeof(buf_layout) - 1] = '\0'; *layout = buf_layout; found = YES; }
        } else if (strncmp(line, "XKBVARIANT=", 11) == 0) {
            char *val = line + 11;
            if (*val == '"') { val++; char *eq = strchr(val, '"'); if (eq) *eq = '\0'; }
            if (val[0]) { strncpy(buf_variant, val, sizeof(buf_variant) - 1); buf_variant[sizeof(buf_variant) - 1] = '\0'; *variant = buf_variant; }
        } else if (strncmp(line, "XKBOPTIONS=", 11) == 0) {
            char *val = line + 11;
            if (*val == '"') { val++; char *eq = strchr(val, '"'); if (eq) *eq = '\0'; }
            if (val[0]) { strncpy(buf_options, val, sizeof(buf_options) - 1); buf_options[sizeof(buf_options) - 1] = '\0'; *options = buf_options; }
        }
    }
    fclose(fp);
    if (found) {
        NSLog(@"KeyboardManager: /etc/default/keyboard layout=%s variant=%s options=%s",
              *layout ? *layout : "(null)",
              *variant ? *variant : "(null)",
              *options ? *options : "(null)");
    }
    return found;
#else
    (void)layout; (void)variant; (void)options;
    return NO;
#endif
}
static const char *efiLocaleToLayout(const char *locale)
{
    if (strcmp(locale, "de") == 0) return "de";
    if (strcmp(locale, "fr") == 0) return "fr";
    if (strcmp(locale, "es") == 0) return "es";
    if (strcmp(locale, "it") == 0) return "it";
    if (strcmp(locale, "pt") == 0) return "pt";
    if (strcmp(locale, "ru") == 0) return "ru";
    if (strcmp(locale, "tr") == 0) return "tr";
    if (strcmp(locale, "he") == 0) return "il";
    if (strcmp(locale, "da") == 0) return "dk";
    if (strcmp(locale, "sv") == 0) return "se";
    if (strcmp(locale, "nb") == 0 || strcmp(locale, "no") == 0) return "no";
    if (strcmp(locale, "fi") == 0) return "fi";
    if (strcmp(locale, "ja") == 0) return "jp";
    if (strcmp(locale, "ko") == 0) return "kr";
    if (strcmp(locale, "zh") == 0) return "cn";
    if (strcmp(locale, "cs") == 0) return "cz";
    if (strcmp(locale, "hu") == 0) return "hu";
    if (strcmp(locale, "pl") == 0) return "pl";
    if (strcmp(locale, "sk") == 0) return "sk";
    if (strcmp(locale, "bg") == 0) return "bg";
    if (strcmp(locale, "uk") == 0) return "ua";
    if (strcmp(locale, "hr") == 0) return "hr";
    if (strcmp(locale, "ro") == 0) return "ro";
    if (strcmp(locale, "sl") == 0) return "si";
    if (strcmp(locale, "et") == 0) return "ee";
    if (strcmp(locale, "lv") == 0) return "lv";
    if (strcmp(locale, "lt") == 0) return "lt";
    if (strcmp(locale, "is") == 0) return "is";
    if (strcmp(locale, "el") == 0) return "gr";
    if (strcmp(locale, "vi") == 0) return "vn";
    if (strcmp(locale, "th") == 0) return "th";
    if (strcmp(locale, "nl") == 0) return "nl";
    if (strcmp(locale, "be") == 0) return "by";
    if (strcmp(locale, "mk") == 0) return "mk";
    if (strcmp(locale, "mt") == 0) return "mt";
    if (strcmp(locale, "en_GB") == 0 || strcmp(locale, "en_IE") == 0) return "gb";
    if (strcmp(locale, "en_CA") == 0) return "ca";
    if (strcmp(locale, "pt_BR") == 0) return "br";
    if (strncmp(locale, "en", 2) == 0) return "us";
    return NULL;
}
static BOOL parseEFIVariable(const unsigned char *data, size_t len,
                             const char **layout, const char **variant,
                             const char **options)
{
    if (len <= 4) {
        NSLog(@"KeyboardManager: EFI NVRAM: data too short (%zu bytes)", len);
        return NO;
    }
    size_t dlen = len - 4;
    const unsigned char *d = data + 4;
    if (dlen > 0 && d[dlen - 1] == '\0') dlen--;
    char str[256];
    size_t slen = 0;
    if (dlen > 0 && d[0] == '\0') {
        for (size_t i = 0; i < dlen && slen < sizeof(str) - 1; i += 2)
            if (i + 1 < dlen)
                str[slen++] = d[i + 1];
            else
                str[slen++] = d[i];
    } else {
        for (size_t i = 0; i < dlen && slen < sizeof(str) - 1; i++)
            str[slen++] = d[i];
    }
    str[slen] = '\0';
    NSLog(@"KeyboardManager: EFI NVRAM raw value: '%s' (len=%zu)", str, slen);
    char *colon = strchr(str, ':');
    if (!colon) {
        NSLog(@"KeyboardManager: EFI NVRAM: no colon found in '%s'", str);
        return NO;
    }
    *colon = '\0';
    *layout = efiLocaleToLayout(str);
    if (!*layout) {
        NSLog(@"KeyboardManager: EFI NVRAM: locale '%s' not in map, fallback to 'us'", str);
        *layout = "us";
    }
    *variant = "";
    *options = "";
    NSLog(@"KeyboardManager: EFI NVRAM locale '%s' -> layout '%s'", str, *layout);
    return YES;
}
static const char *findEfivar(void)
{
    static const char *paths[] = {
        "/usr/local/bin/efivar",
        "/usr/bin/efivar",
        "/bin/efivar",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        if (access(paths[i], X_OK) == 0)
            return paths[i];
    }
    return "efivar";
}
static BOOL detectKeyboardFromEFI(const char **layout,
                                  const char **variant,
                                  const char **options)
{
    unsigned char buf[512];
    size_t n;
    FILE *f = fopen("/sys/firmware/efi/efivars/prev-lang:kbd-7c436110-ab2a-4bbb-a880-fe41995c9f82", "rb");
    if (f) {
        n = fread(buf, 1, sizeof(buf), f);
        fclose(f);
        NSLog(@"KeyboardManager: EFI NVRAM: read %zu bytes from efivarfs", n);
        if (parseEFIVariable(buf, n, layout, variant, options))
            return YES;
    } else {
        NSLog(@"KeyboardManager: EFI NVRAM: efivarfs not available, trying efivar command");
    }
    const char *efivar = findEfivar();
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "%s -p -n 7c436110-ab2a-4bbb-a880-fe41995c9f82-prev-lang:kbd 2>/dev/null", efivar);
    f = popen(cmd, "r");
    if (!f) {
        NSLog(@"KeyboardManager: EFI NVRAM: efivar command not available");
    } else {
        n = fread(buf, 1, sizeof(buf), f);
        int rc = pclose(f);
        if (rc == 0 && n > 0) {
            NSLog(@"KeyboardManager: EFI NVRAM: read %zu bytes from efivar command", n);
            if (parseEFIVariable(buf, n, layout, variant, options))
                return YES;
        } else {
            NSLog(@"KeyboardManager: EFI NVRAM: efivar command returned %d (%zu bytes)", rc, n);
        }
    }
    return NO;
}
@implementation KeyboardManager
@synthesize layout = _layout;
@synthesize variant = _variant;
@synthesize options = _options;
@synthesize model = _model;
@synthesize lastError = _lastError;
- (id)init
{
    self = [super init];
    if (self) {
        _layout = nil;
        _variant = nil;
        _options = nil;
        _model = [@"pc105" copy];
        _lastError = nil;
    }
    return self;
}
- (void)dealloc
{
    [_layout release];
    [_variant release];
    [_options release];
    [_model release];
    [_lastError release];
    [super dealloc];
}
- (BOOL)detectKeyboardWithPasswd:(const struct passwd *)pwd
{
    [_layout release];   _layout = nil;
    [_variant release];  _variant = nil;
    [_options release];  _options = nil;
    [_lastError release]; _lastError = nil;
    const char *c_layout = NULL;
    const char *c_variant = NULL;
    const char *c_options = NULL;
    if (parseEtcDefaultKeyboard(&c_layout, &c_variant, &c_options)) {
        NSLog(@"KeyboardManager: Keyboard source: /etc/default/keyboard");
        goto done;
    }
    if (detectKeyboardFromEFI(&c_layout, &c_variant, &c_options)) {
        NSLog(@"KeyboardManager: Keyboard source: EFI NVRAM");
        goto done;
    }
    if (detectKeyboardFromUSB(&c_layout, &c_variant, &c_options)) {
        NSLog(@"KeyboardManager: Keyboard source: USB RPI keyboard");
        goto done;
    }
    if (!c_layout && detectKeyboardFromDeviceTree(&c_layout, &c_variant, &c_options)) {
        NSLog(@"KeyboardManager: Keyboard source: RPI device-tree");
        goto done;
    }
    if (!c_layout && pwd) {
#if !defined(__linux__)
        login_cap_t *lc = GW_LOGIN_GETPWCLASS((struct passwd *)pwd);
        if (lc) {
            c_layout  = login_getcapstr(lc, "keyboard.layout", NULL, NULL);
            c_variant = login_getcapstr(lc, "keyboard.variant", NULL, NULL);
            c_options = login_getcapstr(lc, "keyboard.options", NULL, NULL);
            login_close(lc);
            if (c_layout)
                NSLog(@"KeyboardManager: Keyboard from login.conf: %s", c_layout);
        }
#else
        (void)pwd;
#endif
    }
    if (!c_layout) {
        c_layout = getenv("XKB_DEFAULT_LAYOUT");
    }
    if (!c_variant) {
        c_variant = getenv("XKB_DEFAULT_VARIANT");
    }
    if (!c_options) {
        c_options = getenv("XKB_DEFAULT_OPTIONS");
    }
    if (!c_layout) {
        NSLog(@"KeyboardManager: Checking /etc/rc.conf for keymap");
        parseRcConfKeymap(&c_layout, &c_variant);
    }
done:
    if (!c_layout) {
        c_layout = "us";
        NSLog(@"KeyboardManager: No keyboard detected from any source, defaulting to 'us'");
    }
    _layout    = [[NSString stringWithUTF8String:c_layout] copy];
    _variant   = (c_variant && c_variant[0])
                    ? [[NSString stringWithUTF8String:c_variant] copy]
                    : [@"" copy];
    _options   = (c_options && c_options[0])
                    ? [[NSString stringWithUTF8String:c_options] copy]
                    : [@"" copy];
    NSLog(@"KeyboardManager: Keyboard layout: %@ variant=%@ options=%@",
          _layout, _variant, _options);
    return YES;
}
- (BOOL)persistConfiguration
{
    if (!_layout) {
        [_lastError release];
        _lastError = [@"No layout detected, cannot persist" copy];
        return NO;
    }
    writeKeyboardConfigFile([_layout UTF8String],
                            [_variant UTF8String],
                            [_options UTF8String]);
    return YES;
}
- (BOOL)applyToXServer
{
    if (!_layout) {
        [_lastError release];
        _lastError = [@"No layout detected, cannot apply" copy];
        return NO;
    }
    return applyKeyboardToXServer([_layout UTF8String],
                                  [_variant UTF8String],
                                  [_options UTF8String]);
}
- (BOOL)setupWithPasswd:(const struct passwd *)pwd
{
    if (![self detectKeyboardWithPasswd:pwd]) return NO;
    [self persistConfiguration];
    [self applyToXServer];
    return YES;
}
@end
