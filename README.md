Raspbian
=========

Literally just pure Raspbian Lite, but with added the ability to run a script on the first boot by putting it onto `/boot/` as `firstboot.sh`.

Repo is inspired by https://github.com/nmcclain/raspberian-firstboot, but has been automated, Dockerized, and fully scripted.

There are 4 ways to get the image:


### 1. Releases

The easiest way is going to [Releases], and downloading the latest one.

Releases are created automatically upon each new Raspbian release, you can see their build log either directly in [Actions tab][actions], or by searching for [`release-pending-approval`][issues] issues. 

[Releases]: /releases
[actions]: /actions
[issues]: /issues?q=is%3Aissue+sort%3Aupdated-desc+label%3Arelease-pending-approval+


### 2. Docker

Second easiest path is (after cloning this repo) running:

1. [`docker build -t builder .`][docker-build]
1. [`docker run --rm --privileged -v="$(pwd)/images/:/raspbian/" builder`][docker-run]

[docker-build]: https://github.com/meeDamian/raspbian/blob/731a1681e0f9dd9ba8b02b810bb473c286b405e7/.github/workflows/release.yml#L34
[docker-run]: https://github.com/meeDamian/raspbian/blob/731a1681e0f9dd9ba8b02b810bb473c286b405e7/.github/workflows/release.yml#L40


### 3. Script

If you're on a Linux box, you can (after cloning this repo) run:

```shell script
./modify-image.sh create images/
```


### 4. Manual

You can also completely ignore all contents of this repo, download Raspbian Lite, and (assuming you have the ability to mount `ext4` on your OS):

1. Mount second partition
1. Install the service, by creating `$MOUNT_PATH/etc/systemd/system/firstboot.service` file, with the following contents:
    ```unit file (systemd)
    [Unit]
    Description=FirstBoot
    After=network.target
    Before=rc-local.service
    ConditionFileNotEmpty=/boot/firstboot.sh
    
    [Service]
    ExecStart=/boot/firstboot.sh
    ExecStartPost=/bin/mv /boot/firstboot.sh /boot/firstboot.sh.done
    Type=oneshot
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
