import os
import smtplib
import sys
from datetime import datetime, timedelta, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

# Hardcoded Target Time in IST (HH:MM AM/PM format)
TARGET_TIME_IST = "11:15 AM" 
RECIPIENT_EMAIL = "muthukumarandev001@gmail.com"

# SMTP Credentials (from existing server config)
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587
SMTP_EMAIL = "dummy@example.com"
SMTP_PASSWORD = "dummy-smtp-password"

def send_helloworld_email(current_time_str):
    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = "Hello World from Cloud Run!"
        msg["From"] = SMTP_EMAIL
        msg["To"] = RECIPIENT_EMAIL

        html_body = f"""
        <html>
            <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
                <h2 style="color: #1a73e8;">Hello World from Google Cloud Run!</h2>
                <p>This email was triggered and sent successfully.</p>
                <p><strong>Trigger Time (IST):</strong> {current_time_str}</p>
                <p><strong>Target Scheduled Time (IST):</strong> {TARGET_TIME_IST}</p>
                <br>
                <hr>
                <p style="font-size: 0.8em; color: #777;">Sent automatically by VAPLI Cloud Run Service.</p>
            </body>
        </html>
        """
        msg.attach(MIMEText(html_body, "html"))

        # Connect and send
        server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
        server.starttls()
        server.login(SMTP_EMAIL, SMTP_PASSWORD)
        server.sendmail(SMTP_EMAIL, [RECIPIENT_EMAIL], msg.as_string())
        server.quit()
        print(f"[+] Email sent successfully to {RECIPIENT_EMAIL}")
        return True
    except Exception as e:
        print(f"[-] Failed to send email: {e}")
        return False

class CloudRunHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Determine IST Time
        ist_tz = timezone(timedelta(hours=5, minutes=30))
        now_ist = datetime.now(ist_tz)
        current_time_str = now_ist.strftime("%I:%M %p")
        
        # Log request and time
        print(f"Received request. Current IST Time: {current_time_str}. Target: {TARGET_TIME_IST}")
        
        # Check if query parameter "force=true" is passed, or if the time matches
        is_force = "force=true" in self.path
        time_matches = current_time_str == TARGET_TIME_IST
        
        email_sent = False
        status_msg = ""
        
        if time_matches or is_force:
            status_msg = f"Triggering email send (Time Match: {time_matches}, Forced: {is_force})."
            print(status_msg)
            email_sent = send_helloworld_email(current_time_str)
        else:
            status_msg = f"Time mismatch. Current: {current_time_str}, Scheduled: {TARGET_TIME_IST}. No email sent. Use ?force=true to test."
            print(status_msg)
            
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        
        response_body = f"""{{
            "status": "success",
            "current_ist_time": "{current_time_str}",
            "target_ist_time": "{TARGET_TIME_IST}",
            "email_triggered": {str(time_matches or is_force).lower()},
            "email_sent_successfully": {str(email_sent).lower()},
            "message": "{status_msg}"
        }}"""
        self.wfile.write(response_body.encode("utf-8"))

def run():
    # Cloud Run passes the port as an environment variable
    port = int(os.environ.get("PORT", 8080))
    server_address = ("", port)
    httpd = HTTPServer(server_address, CloudRunHandler)
    print(f"[*] Starting Hello World Email Server on port {port}...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()

if __name__ == "__main__":
    run()
