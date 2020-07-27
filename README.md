Raspberry Pi OS
================

Official Raspberry Pi OS Lite minimally **modified** with the ability to run a script on the first boot.

Supported script filenames:

* `/boot/firstboot.sh` - Just run the script on the first boot
* `/boot/firstboot-script.sh` - Same as above, **except** _script_ is run with  [`script(1)`][script] for complete session recording, that can be later played back using [`scriptreplay(1)`][replay]

[script]: http://man7.org/linux/man-pages/man1/script.1.html
[replay]: http://man7.org/linux/man-pages/man1/scriptreplay.1.html

Repo is inspired by https://github.com/nmcclain/raspberian-firstboot, but has been automated, Dockerized, and fully scripted.

> **NOTE:** If `firstboot-script.sh` is used, recording of script run is saved as `/boot/firstboot-script-log.out` (timing file alongside as `firstboot-script-log.tm`)

## Usage

1. Download [latest image][latest]
    <details><summary><b>Alternatives?</b></summary>

    If downloading images built by other people is not your thing, you can also:
    
    1. Modify images yourself using provided scripts (in [Docker], or [not]), or even
    1. [Manually] apply all necessary modifications
    </details>
    
    [latest]: #1-releases
    [docker]: #2-docker
    [not]: #3-script
    [manually]: #4-manual
1. Burn it into a MicroSD Card
    <details><summary><b>How?</b></summary>
    
    1. Probably the easiest is to use [Etcher]
    1. Another way is [using `dd`][dd] on Linux:
        ```shell script
        dd bs=4M if=path/to/downloaded/file.img of=/dev/sdX conv=fsync
        ```
    1. Or MacOS:
        ```shell script
        dd bs=4M if=path/to/downloaded/file.img of=/dev/diskX conv=fsync
        ```
        
    **NOTE:** `boot` partition will usually get mounted as `/Volumes/boot/` on MacOS, and _probably_ `/mnt/boot/` on Linux.
    </details>
    
    [Etcher]: https://www.balena.io/etcher/
    [dd]: https://www.raspberrypi.org/documentation/installation/installing-images/linux.md
1. Mount it
    <details><summary><b>How?</b></summary>
    
    1. **\[MacOS\]** Simply re-inserting the card should do the trick, if not then `diskutil`, or `Disk Utility` should help
    1. **\[Linux\]** Hard to say exactly, but sth like:
    ```sh
    mkdir -p /mnt/boot/
    sudo mount /dev/sdX /mnt/boot/
    ```
    </details>

1. Add your script & mark it as executable
    ```sh
    # MacOS example:
    cd /Volumes/boot/
    
    cat <<EOF > firstboot-script.sh
    #!/bin/sh -e
    
    echo "Hello World!"
    EOF
    
    chmod +x firstboot-script.sh
    ```
1. Safely eject, move the card into Raspberry Pi, and power it on

## Download

There are 4 possible ways, numbered from easiest to most manual.

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

[`mount`]: https://github.com/meeDamian/raspios/blob/d3af7a29ee4c9cd09aae68badec95725c58c7010/modify-image.sh#L199


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
