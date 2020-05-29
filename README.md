Raspberry Pi OS
================

Literally just pure Raspberry Pi OS Lite, but with added the ability to run a script on the first boot by putting it onto `/boot/` as either:

* `/boot/firstboot.sh` - Run provided script directly
* `/boot/firstboot-script.sh` - Run via [`script(1)`][script] for complete session recording, that can be later played back using [`scriptreplay(1)`][replay]

[script]: http://man7.org/linux/man-pages/man1/script.1.html
[replay]: http://man7.org/linux/man-pages/man1/scriptreplay.1.html

Repo is inspired by https://github.com/nmcclain/raspberian-firstboot, but has been automated, Dockerized, and fully scripted.

There are 4 ways to get the image:


### 1. Releases

The easiest way is going to [Releases], and downloading the latest one.

Releases are created automatically upon each new Raspberry Pi OS release, you can see their build log either directly in [Actions tab][actions], or by searching for [`release-pending-approval`][issues] issues. 

[Releases]: https://github.com/meeDamian/raspios/releases
[actions]: https://github.com/meeDamian/raspios/actions
[issues]: https://github.com/meeDamian/raspios/issues?q=is%3Aissue+sort%3Aupdated-desc+label%3Arelease-pending-approval+


### 2. Docker

Second easiest path is (after cloning this repo) running:

1. [`docker build -t builder .`][docker-build]
1. [`docker run --rm --privileged -v="$(pwd)/images/:/raspios/" builder`][docker-run]

[docker-build]: https://github.com/meeDamian/raspios/blob/731a1681e0f9dd9ba8b02b810bb473c286b405e7/.github/workflows/release.yml#L34
[docker-run]: https://github.com/meeDamian/raspios/blob/731a1681e0f9dd9ba8b02b810bb473c286b405e7/.github/workflows/release.yml#L40

> **NOTE:** `--privileged` flag is required because [`mount`]ing a filesystem requires root.
>
>**NOTE_2:** Alternatively [`./run-in-docker.sh`][run] can be run to achieve the same effect.

[run]: /run-in-docker.sh


### 3. Script

If you're on a Linux box, you can (after cloning this repo) run:

```shell script
./modify-image.sh create images/
```

> **NOTE:** `sudo` might be required because [`mount`]ing a filesystem requires root.

[`mount`]: https://github.com/meeDamian/raspios/blob/master/modify-image.sh#L166


### 4. Manual

You can also completely ignore all contents of this repo, download Raspberry Pi OS Lite, and (assuming you have the ability to mount `ext4` on your OS):

> **NOTE: For `firstboot-script.service` see [here].**

[here]: /firstboot-script.service

1. Mount second partition
1. Install the service, by creating `$MOUNT_PATH/etc/systemd/system/firstboot.service` file, with the following contents:
    ```unit file (systemd)
    [Unit]
    Description=FirstBoot
    After=network.target
    Before=rc-local.service
    ConditionFileNotEmpty=/boot/firstboot.sh
    
    [Service]
    Type=oneshot
    ExecStart=/boot/firstboot.sh
    ExecStartPost=/bin/mv /boot/firstboot.sh /boot/firstboot.sh.done
    RemainAfterExit=no
    
    [Install]
    WantedBy=multi-user.target
    ```
1. Enable the service by running:
    ```shell script
    cd $MOUNT_PATH/etc/systemd/system/multi-user.target.wants/ && \
        ln -s /etc/systemd/system/firstboot.service . # No $MOUNT_PATH(!)
    ```
1. `umount` the image
1. Burn it to a card
