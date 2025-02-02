import sys
import smtplib
import argparse
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Send an email using SMTP.')
parser.add_argument('--smtp_server', required=True, help='SMTP server address')
parser.add_argument('--smtp_port', type=int, required=True, help='SMTP server port')
parser.add_argument('--smtp_user', required=True, help='SMTP username')
parser.add_argument('--smtp_password', required=True, help='SMTP password')
parser.add_argument('--from_email', required=True, help='Sender email address')
parser.add_argument('--to_email', required=True, help='Recipient email address')
parser.add_argument('--subject', required=True, help='Email subject')
parser.add_argument('--body', required=True, help='Email body')
args = parser.parse_args()

# Create the email message
msg = MIMEMultipart()
msg['From'] = args.from_email
msg['To'] = args.to_email
msg['Subject'] = args.subject
msg.attach(MIMEText(args.body, 'plain'))

# Send the email
try:
    server = smtplib.SMTP_SSL(args.smtp_server, args.smtp_port)
    server.login(args.smtp_user, args.smtp_password)
    server.sendmail(args.from_email, args.to_email, msg.as_string())
    server.quit()
except Exception as e:
    print(f"Failed to send email: {e}", file=sys.stderr)
