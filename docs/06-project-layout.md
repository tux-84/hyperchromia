# Project layout

```
hyperchromia/
├── install.sh                   entry point: build only, or build + flash a USB stick
├── config.env                   build-time defaults (hostname, HyperHDR version)
├── authorized_keys              your SSH public key(s), gitignored
├── VERSION                      release version
├── scripts/
│   ├── build.sh                 build script
│   └── make-usb.sh              USB installer/updater stick builder
└── build/                       Buildroot external tree
    ├── assets/                  README images
    ├── board/                   kernel config, partition layout, boot scripts
    └── package/hyperhdr/        HyperHDR build recipe
```
