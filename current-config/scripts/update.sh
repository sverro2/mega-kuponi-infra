#!/bin/bash
echo "The update process has been initiated"
echo "NOTICE: when an error occurs during this process, no further action is taken (the mega-kuponi service will keep running as is)"
echo

set -e

# Request root privilege
if [[ "$EUID" = 0 ]]; then
    echo "(1) already root"
else
    echo "We need your account password:"
    sudo -k # make sure to ask for password on next sudo
    if sudo true; then
        echo "(2) correct password"
    else
        echo "(3) wrong password"
        exit 1
    fi
fi

# Pull sources from repository
eval `ssh-agent`
ssh-add ~/.ssh/id-dev

cd /home/ana/source/mega-kuponi/
git checkout main
git pull

# Compile sources
cargo build --release

# Update template files
echo "Updating template files"
sudo cp -r -u templates/ /var/www/application/

# Update vector images
echo "Updating vector images"
sudo cp -r -u static/images/vectors/ /var/www/resources/images/

# Stopping service to prepare for new install
echo ""
echo "The mega-kuponi service is stopped in preparation of the new executable"
sudo systemctl stop mega-kuponi.service

# Copy new executable to location
echo "Copying executable to target location"
sudo cp target/release/mega-kuponi /var/www/application/mega-kuponi

# Rebooting to new install
echo "The new system is being started..."
echo ""

sudo systemctl start mega-kuponi.service

echo "The update process is succesfully finished! The new service is online :-)"
echo ""

sleep 5

 ./scripts/bash/ftl-validation/run.sh http://localhost:8000
