cd /opt/otrs/var/cron
for foo in *.dist; do cp $foo `basename $foo .dist`; done
exit
bin/Cron.sh start
clear
sudo mysql_secure_installation
exit
/opt/otrs/bin/Cron.sh start
clear
/opt/otrs/bin/Cron.sh status
/opat/otrs/bin/otrs.Daemon.pl status
/opt/otrs/bin/otrs.Daemon.pl status
cd
clear
/opt/otrs/bin/Cron.sh start
/opt/otrs/bin/otrs.Daemon.pl status
su otrs
ext
exit
/opt/otrs/bin/Cron.sh start
