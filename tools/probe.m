// probe.m — 枚举 DFRFoundation 全部导出符号（直接走 Mach-O export trie，不猜名字）
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

static void walkTrie(const uint8_t *base, const uint8_t *node, const char *prefix,
                     const char **out, int *count, int max) {
    uint8_t termSize = node[0];
    const char *info = (const char *)(node + 1);
    for (uint8_t i = 0; i < termSize; i++) {
        uint64_t flags = 0; int off = 0;
        const uint8_t *p = (const uint8_t *)info + i;
        // uleb128 flags
        do { flags |= (uint64_t)(*p & 0x7f) << off; off += 7; } while (*p++ & 0x80);
        if ((flags & 0x08) == 0 && *count < max) {   // 只取常规导出（跳过 re-export）
            char full[512];
            snprintf(full, sizeof full, "%s", prefix);
            out[(*count)++] = strdup(full);
        }
    }
    info += termSize;
    if (!(info[0] & 0x80)) return;
    const uint8_t *p = (const uint8_t *)info;
    while (*p) {
        uint8_t edgeLen = *p & 0x7f;
        p++;
        char next[512];
        snprintf(next, sizeof next, "%s%.*s", prefix, edgeLen, p);
        p += edgeLen;
        uint64_t childOff = 0; int shift = 0;
        do { childOff |= (uint64_t)(*p & 0x7f) << shift; shift += 7; } while (*p++ & 0x80);
        walkTrie(base, base + childOff, next, out, count, max);
    }
}

int main(void) {
    @autoreleasepool {
        void *h = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
                         RTLD_NOW);
        if (!h) { printf("dlopen FAILED: %s\n", dlerror()); return 1; }

        Dl_info di;
        dladdr(dlsym(h, "DFRSetStatus"), &di);
        const uint8_t *mh = (const uint8_t *)di.dli_fbase;
        const struct mach_header_64 *hdr = (const struct mach_header_64 *)mh;
        printf("image base = %p, magic=%08x, ncmds=%u\n", mh, hdr->magic, hdr->ncmds);

        uint32_t exportsOff = 0, exportsSize = 0;
        uint64_t textVm = 0, leVm = 0, leFile = 0;
        const uint8_t *cmd = mh + sizeof(struct mach_header_64);
        for (uint32_t i = 0; i < hdr->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)cmd;
            if (lc->cmd == LC_DYLD_EXPORTS_TRIE) {
                const struct linkedit_data_command *ld = (const struct linkedit_data_command *)lc;
                exportsOff = ld->dataoff; exportsSize = ld->datasize;
            }
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *sg = (const struct segment_command_64 *)lc;
                if (strcmp(sg->segname, "__TEXT") == 0) textVm = sg->vmaddr;
                if (strcmp(sg->segname, "__LINKEDIT") == 0) { leVm = sg->vmaddr; leFile = sg->fileoff; }
            }
            cmd += lc->cmdsize;
        }
        // 共享缓存里 dataoff 是"缓存文件偏移"，要换算成映射地址
        uint64_t trieVm = leVm + (exportsOff - leFile);
        const uint8_t *trie = mh + (trieVm - textVm);
        printf("exports trie: off=%u size=%u -> mapped @ %p\n\n", exportsOff, exportsSize, trie);
        if (!exportsOff) { printf("no exports trie\n"); return 1; }

        const char *out[4096]; int count = 0;
        walkTrie(trie, trie, "", out, &count, 4096);
        printf("共 %d 个导出符号：\n", count);
        for (int i = 0; i < count; i++) printf("  %s\n", out[i]);
    }
    return 0;
}
