function ebpf-env --description "Set up eBPF build environment"
    set -x BPF2GO_CC clang-20
    set -x BPF2GO_STRIP llvm-strip-20
    set -x BPF2GO_OBJCOPY llvm-objcopy-20
    set -x BPF2GO_CFLAGS "-O2 -g -Wall -Werror"
    echo "eBPF environment configured for clang-20"
end
