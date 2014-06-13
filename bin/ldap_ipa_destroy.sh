#!/bin/bash

echo "Warning ! This is just a script for "
echo "Development testing to remove IPA "
echo "In general, we dont expect IPA to reliably "
echo "support idempotent uninstall/reinstall cycles"

  sudo ipa-server-install --uninstall -U
  sudo ipa-server-install --uninstall -U
  sudo ipa-server-install --uninstall -U
  sudo pkidestroy -s CA -i pki-tomcat
  sudo rm -rf /var/log/pki/pki-tomcat
  sudo rm -rf /etc/sysconfig/pki-tomcat
  sudo rm -rf /etc/sysconfig/pki/tomcat/pki-tomcat
  sudo rm -rf /var/lib/pki/pki-tomcat
  sudo rm -rf /etc/pki/pki-tomcat
  sudo yum remove freeipa-* -y
