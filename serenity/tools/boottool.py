#!/usr/bin/env python3
import sys, struct, hashlib, os

PAGE = None

def align(v, a):
    return ((v + a - 1) // a) * a

def parse(raw):
    if raw[:8] != b'ANDROID!':
        raise SystemExit('not an Android boot image')
    h = bytes(raw[:4096])
    ver = struct.unpack_from('<I', h, 40)[0]
    fields = {
        'kernel_size', 'kernel_addr', 'ramdisk_size', 'ramdisk_addr',
        'second_size', 'second_addr', 'tags_addr', 'page_size',
        'header_version', 'os_version', 'name', 'cmdline', 'id',
    }
    got = {}
    got['kernel_size'], got['kernel_addr'], got['ramdisk_size'], got['ramdisk_addr'], \
    got['second_size'], got['second_addr'], got['tags_addr'], got['page_size'], \
    got['header_version'], got['os_version'] = struct.unpack_from('<10I', h, 8)
    got['name'] = h[48:64].rstrip(b'\0').decode('latin1')
    got['cmdline'] = h[64:576].rstrip(b'\0').decode('latin1')
    got['id'] = h[576:608]
    extra_cmdline = b''
    recovery_off = recovery_size = header_size = dtb_size = dtb_addr = None
    base = 608
    if ver >= 1:
        pass
    if ver == 2:
        recovery_dtbo_size, recovery_dtbo_offset, header_size = \
            struct.unpack_from('<IQI', h, base)
    elif ver == 3:
        header_size = struct.unpack_from('<I', h, base)[0]
    elif ver == 4:
        header_size, dtb_size, dtb_addr = struct.unpack_from('<IIQ', h, base)
    elif ver == 0:
        pass
    else:
        raise SystemExit(f'unsupported/unknown header_version {ver}')
    if ver >= 2:
        extra_cmdline = h[608:1632].rstrip(b'\0').decode('latin1')
    return got, ver, extra_cmdline, recovery_size, recovery_off, header_size, dtb_size, dtb_addr

def sections(info, ver, dtb_size, header_size, raw):
    page = info['page_size'] or 4096
    pos = header_size
    out = {}
    order = ['kernel', 'ramdisk', 'second']
    if ver == 4:
        order.append('dtb')
    sizes = {
        'kernel': info['kernel_size'],
        'ramdisk': info['ramdisk_size'],
        'second': info['second_size'],
        'dtb': dtb_size if ver == 4 else 0,
    }
    for name in order:
        s = sizes[name]
        if s:
            out[name] = raw[pos:pos + s]
            out[name + '_off'] = pos
        pos = align(pos + s, page)
    end = pos
    return out, end

def print_info(path):
    raw = open(path, 'rb').read()
    got, ver, extra, rs, ro, hsize, dtsz, dtaddr = parse(raw)
    print('== header ==')
    print(f'header_version : {ver}')
    print(f'page_size      : {got["page_size"]}')
    print(f'header_size    : {hsize}')
    print(f'kernel_size    : {got["kernel_size"]}')
    print(f'kernel_addr    : 0x{got["kernel_addr"]:x}')
    print(f'ramdisk_size   : {got["ramdisk_size"]}')
    print(f'ramdisk_addr   : 0x{got["ramdisk_addr"]:x}')
    print(f'second_size    : {got["second_size"]}')
    print(f'tags_addr      : 0x{got["tags_addr"]:x}')
    print(f'os_version     : 0x{got["os_version"]:08x}')
    print(f'name           : {got["name"]!r}')
    if ver >= 2:
        print(f'dtb_size       : {dtsz}   dtb_addr: 0x{dtaddr:016x}')
    print(f'cmdline        : {got["cmdline"]!r}')
    print(f'extra_cmdline  : {extra!r}')
    secs, end = sections(got, ver, dtsz, hsize, raw)
    print('== sections ==')
    for name in secs:
        if name.endswith('_off'):
            print(f'{name:12s} 0x{secs[name]:08x} (absolute offset {secs[name]})')
    print(f'content_end    : {end} (0x{end:x})  file_size {len(raw)}')
    trailer = raw[end:]
    print(f'trailer_len    : {len(trailer)}')
    if len(trailer) >= 64:
        print(f'last64 magic   : {trailer[-64:][:4]!r}')
        print(f'file size hex  : 0x{len(raw):x}')
        # scan for AVBf / AVB0 header
        for m in (b'AVBf', b'AVB0'):
            idx = raw.rfind(m)
            print(f'{m!r} last at     : {idx} (0x{idx:x})' if idx >= 0 else f'{m!r} not found')
    print('== header+ver-derived tables ==')
    print(f'id(sha256 kernel||ramdisk||second)= {got["id"].hex()}')

def build_v4_unsigned(src, newkernel, outpath, append_cmdline):
    """Build a header-v4 kernel-only boot image mirroring the stock layout:
    [4096-byte header][kernel padded to 4096][zeros to partition size].
    AVB vbmeta/footer that shipped in the stock image are dropped (the image
    becomes unsigned; on an unlocked bootloader AVB is not enforced)."""
    raw = open(src, 'rb').read()
    part_size = len(raw)
    new_k = open(newkernel, 'rb').read()
    print(f'new kernel bytes: {len(new_k)}')
    if 4096 + align(len(new_k), 4096) > part_size:
        raise SystemExit('kernel too large for partition size %d' % part_size)

    page = 4096
    header = bytearray(page)
    # fields per boot_img_hdr_v4 (see mkbootimg.h)
    struct.pack_into('<8s', header, 0, b'ANDROID!')
    struct.pack_into('<I', header, 8, len(new_k))      # kernel_size
    struct.pack_into('<I', header, 36, page)           # page_size (legacy, unused in v4)
    struct.pack_into('<I', header, 40, 4)              # header_version
    if append_cmdline:
        b = append_cmdline.encode()
        if len(b) > 512:
            raise SystemExit('cmdline exceeds 512')
        struct.pack_into('<512s', header, 64, b)       # cmdline
    struct.pack_into('<I', header, 608, 4096)          # header_size
    struct.pack_into('<I', header, 612, 0)             # dtb_size (none in boot.img)
    struct.pack_into('<Q', header, 616, 0)             # dtb_addr
    new_id = hashlib.sha256(new_k).digest()            # id = sha256(kernel||ramdisk||second)
    struct.pack_into('<32s', header, 576, new_id)

    out = bytearray()
    out += header
    out += new_k
    out += b'\0' * (align(len(new_k), page) - len(new_k))
    if len(out) > part_size:
        raise SystemExit('kernel too large: %d > %d' % (len(out), part_size))
    out += b'\0' * (part_size - len(out))
    open(outpath, 'wb').write(out)
    print(f'wrote {outpath} ({len(out)} bytes)')

def repack_keepavb(src, newkernel, outpath, append_cmdline):
    """Repack mirroring stock EXACTLY (header fields untouched, AVB vbmeta struct and
    footer kept byte-for-byte at their original offsets) and only:
      - replace kernel section (pad/zero to the original kernel slot),
      - append cmdline,
      - recompute id.
    Works when the new kernel fits inside the original kernel slot (pad with zeros)."""
    raw = open(src, 'rb').read()
    got, ver, extra, rs, ro, hsize, dtsz, dtaddr = parse(raw)
    page = got['page_size'] or 4096
    kern = got['kernel_size']
    if isinstance(newkernel, (bytes, bytearray, memoryview)):
        new_k = bytes(newkernel)
    else:
        new_k = open(newkernel, 'rb').read()
    print(f'old kernel slot {kern}, new kernel {len(new_k)}')

    cmdline = got['cmdline']
    if append_cmdline:
        if cmdline and not cmdline.endswith(' '):
            cmdline += ' '
        cmdline += append_cmdline
    if len(cmdline.encode()) > 512:
        raise SystemExit('cmdline exceeds 512')

    avb0 = raw.find(b'AVB0')
    avbf = raw.find(b'AVBf')
    print(f'AVB0 at {avb0}, AVBf at {avbf}')
    if avb0 < 0 or avbf <= avb0:
        print('WARNING: no AVB vbmeta/footer found in source; falling back to v4kernelonly layout')
        build_v4_unsigned(src, newkernel, outpath, append_cmdline)
        return

    hdr_len = 4096
    kernel_off = hdr_len
    avail = avb0 - kernel_off              # bytes available for kernel slot
    if len(new_k) > avail:
        print(f'new kernel {len(new_k)} > available slot {avail}; must move AVB blocks')
        # build: header + kernel(padded) + pad gap?, then re-emit vbmeta+footer,
        # updating the footer's vbmeta_offset to the new location.
        # Preserve the original vbmeta struct blob and footer blob.
        # Determine vbmeta struct size: from footer's original_image_size/vbmeta_offset.
        import struct as S
        # footer is at avbf, len=64; vbmeta_offset field at footer+16 (BE u64)
        vbmeta_offset = S.unpack('>Q', raw[avbf + 16:avbf + 24])[0]
        orig_img_size = S.unpack('>Q', raw[avbf + 8:avbf + 16])[0]
        vbmeta_blob = raw[vbmeta_offset:vbmeta_offset + (avbf - vbmeta_offset)]
        print(f'vbmeta_offset {vbmeta_offset}, struct size {len(vbmeta_blob)}')
        header = bytearray(raw[:hdr_len])
        S.pack_into('<I', header, 8, len(new_k))
        S.pack_into('<512s', header, 64, cmdline.encode())
        S.pack_into('<32s', header, 576, hashlib.sha256(new_k).digest())
        out = bytearray(header)
        out += new_k
        pos = hdr_len + len(new_k)
        pad_to = align(pos, page)
        out += b'\0' * (pad_to - pos)
        # place vbmeta struct right after kernel (aligned), then zeros to footer...
        out += vbmeta_blob
        after = len(out)
        # rebuild footer with updated vbmeta_offset (absolute) and original_image_size
        footer = bytearray(raw[avbf:avbf + 64])
        S.pack_into('>Q', footer, 8, after - 64 - len(vbmeta_blob) + 64)  # placeholder
        # original_image_size = size of everything that precedes the vbmeta block
        S.pack_into('>Q', footer, 8, after - len(vbmeta_blob))
        S.pack_into('>Q', footer, 16, after - len(vbmeta_blob))
        if len(out) < len(raw):
            out += b'\0' * (len(raw) - len(out))
        elif len(out) > len(raw):
            out += b'\0' * (align(len(out), 4096) - len(out))
        open(outpath, 'wb').write(out)
        print(f'wrote {outpath} ({len(out)} bytes), vbmeta moved')
        return

    out = bytearray(raw)
    # zero the old kernel slot, then write the new kernel from the slot start
    out[kernel_off:avb0] = b'\0' * (avb0 - kernel_off)
    out[kernel_off:kernel_off + len(new_k)] = new_k
    struct.pack_into('<I', out, 8, len(new_k))
    struct.pack_into('<512s', out, 64, cmdline.encode())
    struct.pack_into('<32s', out, 576, hashlib.sha256(new_k).digest())
    open(outpath, 'wb').write(out)
    print(f'wrote {outpath} ({len(out)} bytes), AVB kept in place')

def patch_cmdline_keepavb(src, outpath, append_cmdline):
    """Patch ONLY the command line of a stock boot image, preserving everything
    else byte-for-byte (kernel, AVB vbmeta struct + footer). This is the safe
    'boot_permissive' operation for Redmi A5 / Unisoc devices: the bootloader
    hard-rejects boot images whose AVB region is removed."""
    raw = open(src, 'rb').read()
    got, ver, extra, rs, ro, hsize, dtsz, dtaddr = parse(raw)
    kern = raw[4096:4096 + got['kernel_size']]
    print(f'kernel section: {len(kern)} bytes (kept unchanged)')
    repack_keepavb(src, kern, outpath, append_cmdline)

def extract_kernel(src, outpath):
    raw = open(src, 'rb').read()
    got, ver, extra, rs, ro, hsize, dtsz, dtaddr = parse(raw)
    kern = raw[4096:4096 + got['kernel_size']]
    open(outpath, 'wb').write(kern)
    print(f'wrote {outpath} ({len(kern)} bytes)')

def repack(src, newkernel, outpath, append_cmdline, mode='v4kernelonly'):
    raw = open(src, 'rb').read()
    got, ver, extra, rs, ro, hsize, dtsz, dtaddr = parse(raw)
    if mode == 'v4kernelonly':
        build_v4_unsigned(src, newkernel, outpath, append_cmdline)
        return
    print(f'old kernel bytes: {got["kernel_size"]}')
    new_k = open(newkernel, 'rb').read()

    cmdline = got['cmdline']
    if append_cmdline:
        if cmdline and not cmdline.endswith(' '):
            cmdline += ' '
        cmdline += append_cmdline
    if len(cmdline.encode()) > 512:
        raise SystemExit('cmdline exceeds 512 bytes')

    page = got['page_size'] or 4096
    header = bytearray(raw[:hsize] if hsize else raw[:4096])
    struct.pack_into('<I', header, 8, len(new_k))
    struct.pack_into('<512s', header, 64, cmdline.encode())
    new_id = hashlib.sha256(new_k).digest()
    struct.pack_into('<32s', header, 576, new_id)

    out = bytearray(header)
    def add(s):
        nonlocal out
        out += s
        pad = align(len(s), page) - len(s)
        out += b'\0' * pad
    add(new_k)
    if got['ramdisk_size']:
        # ramdisk wasn't captured; rebuild copying slice is messy, error out.
        raise SystemExit('ramdisk present: use a full unpacker, this mode is kernel-only')
    if ver == 4 and dtsz:
        raise SystemExit('dtb in boot.img: use a full unpacker, this mode is kernel-only')

    if len(out) < len(raw):
        out += b'\0' * (len(raw) - len(out))
    elif len(out) > len(raw):
        print(f'WARNING: new image larger than original ({len(out)} > {len(raw)})')
    open(outpath, 'wb').write(out)
    print(f'wrote {outpath} ({len(out)} bytes)')

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'info':
        print_info(sys.argv[2])
    elif cmd == 'patch':
        src, outp = sys.argv[2], sys.argv[3]
        append = None
        if '--append' in sys.argv:
            append = sys.argv[sys.argv.index('--append') + 1]
        patch_cmdline_keepavb(src, outp, append)
    elif cmd == 'extract':
        extract_kernel(sys.argv[2], sys.argv[3])
    elif cmd == 'repack':
        src, newk, outp = sys.argv[2], sys.argv[3], sys.argv[4]
        append = None
        mode = 'default'
        if '--append' in sys.argv:
            append = sys.argv[sys.argv.index('--append') + 1]
        if '--mode' in sys.argv:
            mode = sys.argv[sys.argv.index('--mode') + 1]
        if mode in ('keepavb',):
            repack_keepavb(src, newk, outp, append)
        else:
            repack(src, newk, outp, append, mode)
    else:
        raise SystemExit('usage: boottool.py info|repack ...')