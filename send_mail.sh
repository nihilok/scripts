#!/bin/bash

DIRNAME=$(dirname $0)

python3 $DIRNAME/send_mail.py --smtp_server $MAIL_SERVER --smtp_port $MAIL_PORT --smtp_user $MAIL_USER --smtp_password $MAIL_PASSWD --from_email $MAIL_USER --to_email "$1" --subject "$2" --body "$3"
