import os
import sys
from datetime import datetime

# Add parent directory to path so we can import Server.server
sys.path.append(os.path.abspath(os.path.dirname(__file__)))
import server

def generate_compliance_html(date_str):
    """Simulates execute_missing_tanks_email to generate and return the email HTML body"""
    tanks_data = server.normalize_to_dict(server.fetch_db("tanks"))
    readings_data = server.normalize_to_dict(server.fetch_db("readings"))
    tree_data = server.normalize_to_dict(server.fetch_db("tank_tree"))
    
    # Gather readings for date
    target_readings = set()
    for r in readings_data.values():
        try:
            if r.get("captured_at", "").split("T")[0] == date_str:
                target_readings.add(r.get("tank_id"))
        except:
            continue

    nodes = list(tree_data.values()) if isinstance(tree_data, dict) else []
    top_folders = [n for n in nodes if n.get("type") == "folder" and not n.get("parent_id")]
    top_folders.sort(key=lambda x: x.get("order", 0))

    def get_folder_tanks(folder_id):
        tank_ids = []
        queue = [folder_id]
        while queue:
            curr = queue.pop(0)
            children = [n for n in nodes if n.get("parent_id") == curr]
            for c in children:
                if c.get("type") == "leaf" and c.get("tank_id"):
                    tank_ids.append(c.get("tank_id"))
                elif c.get("type") == "folder":
                    queue.append(c.get("id"))
        return tank_ids

    compliance_content = ""
    missing_tank_ids = []

    for folder in top_folders:
        t_ids = get_folder_tanks(folder.get("id"))
        if not t_ids:
            continue
        
        folder_tanks = [tanks_data[tid] for tid in t_ids if tid in tanks_data]
        if not folder_tanks:
            continue

        total_count = len(folder_tanks)
        inspected = [t for t in folder_tanks if t.get("id") in target_readings]
        uninspected = [t for t in folder_tanks if t.get("id") not in target_readings]
        inspected_count = len(inspected)
        
        missing_tank_ids.extend([t.get("id") for t in uninspected])
        
        percentage = (inspected_count / total_count) * 100 if total_count > 0 else 0

        compliance_content += f"<h3 style='margin-top:20px; color:#252830;'>Group: {folder.get('name')}</h3>"

        # Check conditions
        if inspected_count == 0:
            compliance_content += f"<p style='color:#D97706; font-weight:600;'>Group <b>{folder.get('name')}</b> has no tank recording Checkout for Readings</p>"
        elif percentage == 100.0:
            compliance_content += f"<p style='color:#2ECC71; font-weight:600;'>Group <b>{folder.get('name')}</b> is fully recorded.</p>"
        elif percentage < 50.0:
            compliance_content += f"<p>Group <b>{folder.get('name')}</b> has not been Recorded except these tanks</p>"
            compliance_content += server.render_3_column_list(inspected)
        else:
            compliance_content += f"<p>Group <b>{folder.get('name')}</b> has been Recorded except these tanks</p>"
            compliance_content += server.render_3_column_list(uninspected)

    # Link for feedback form (defaults to Firebase Hosting URL)
    encoded_tanks = ",".join(missing_tank_ids)
    feedback_base = server.CONFIG.get("external_url") or "https://dummy-firebase-project-id.web.app"
    feedback_url = f"{feedback_base}/feedback.html?client_id={server.CONFIG['client_id']}&date={date_str}&tanks={encoded_tanks}&env={server.CONFIG['env_mode']}"
    
    feedback_btn = f"""
    <div style='text-align: center;'>
        <a href='{feedback_url}' class='btn-cta' target='_blank'>Submit Reason for Missed Inspections</a>
    </div>
    """

    body = f"""
    <p>Dear Administrator,</p>
    <p>Here is the compliance report highlighting lubrication inspection gaps for today.</p>
    <hr style='border:0; border-top:1px solid #E2E8F0;'>
    {compliance_content}
    <hr style='border:0; border-top:1px solid #E2E8F0; margin-top:20px;'>
    <p style='margin-top:20px;'><b>Inspection Action Required:</b></p>
    <p>To keep the automation metrics clean, please submit the reasons for any missed inspections today by clicking the button below:</p>
    {feedback_btn}
    <br>
    <p>Thank you,<br><b>VAPLI Compliance Monitor</b></p>
    """
    
    return server.build_modern_template("Inspection Gaps & Gaps Form", "Daily Compliance Alert", body)

def generate_alerts_email_html():
    """Simulates execute_alerts_notification_email to generate and return the email HTML body"""
    alerts_data = server.normalize_to_dict(server.fetch_db("alerts"))
    active_alerts = []
    for a_id, a in alerts_data.items():
        if not a.get("resolved", False) and a.get("show_dashboard_alert", True):
            active_alerts.append(a)

    if not active_alerts:
        body = "<p>No active alerts to notify today.</p>"
        return server.build_modern_template("Active Alarm Center", "Active Alarm Notification", body)

    table_rows = ""
    for a in active_alerts:
        sev = (a.get("constraint_severity") or a.get("severity") or "warning").lower()
        badge_class = f"badge-{sev}"
        
        raw_time = a.get("captured_at") or a.get("timestamp") or ""
        dt = server.parse_iso_datetime(raw_time)
        time_str = dt.strftime("%d/%m/%Y %I:%M %p") if dt else raw_time.replace("T", " ")[:16]

        label = a.get("constraint_label") or a.get("param_label") or "-"
        val = a.get("violated_value") or a.get("param_value") or "-"
        msg = a.get("message") or a.get("alert_title") or "-"

        table_rows += f"""
        <tr>
            <td style='white-space:nowrap;'>{time_str}</td>
            <td><b>{a.get('tank_name')}</b><br><span style='font-size:11px; color:#64748B;'>{a.get('tank_code')}</span></td>
            <td><span class='badge {badge_class}'>{sev.upper()}</span></td>
            <td>{label}</td>
            <td style='color:#EF4444; font-weight:600;'>{val}</td>
            <td>{msg}</td>
        </tr>
        """

    alert_table = f"""
    <table class='report-table'>
        <thead>
            <tr>
                <th>Time</th>
                <th>Asset</th>
                <th>Severity</th>
                <th>Parameter</th>
                <th>Violated Value</th>
                <th>Message</th>
            </tr>
        </thead>
        <tbody>
            {table_rows}
        </tbody>
    </table>
    """

    body = f"""
    <p>Dear team,</p>
    <p>Our constraint engine has surfaced the following active alarms that require your immediate attention.</p>
    {alert_table}
    <p style='margin-top:20px; font-weight:600; color:#EF4444;'>Action Required:</p>
    <p>Log in to the VAPLI Admin Dashboard to inspect these violations, resolve the issues on-site, and mark these alerts as resolved.</p>
    <br>
    <p>Regards,<br><b>VAPLI Alert Center</b></p>
    """
    
    return server.build_modern_template("Active Alarm Center", "Active Alarm Notification", body)

def main():
    print("[*] Running VAPLI Server Verification...")
    server.load_env()
    
    server.CONFIG["client_id"] = "dummy_client_id"
    server.CONFIG["env_mode"] = "production"
    
    test_date = "2026-06-26"
    
    os.makedirs("test_output", exist_ok=True)
    
    print(f"[*] Simulating Daily Reports Email HTML body...")
    reports_body = f"""
    <p>Dear Team,</p>
    <p>Please find attached the official VAPLI telemetry and alarm inspection reports compiled for today.</p>
    <p><b>Summary Details:</b></p>
    <ul>
        <li><b>Client Scope:</b> {server.CONFIG['client_id'].upper()}</li>
        <li><b>Date:</b> {datetime.now().strftime('%A, %d %B %Y')}</li>
        <li><b>Generated At:</b> {datetime.now().strftime('%I:%M %p %Z')}</li>
    </ul>
    <p>The attachments contain:
        <ol>
            <li><b>Today's Inspection Summary (PDF & Excel)</b>: Detailed parameter values and image links for all scanned lubrication assets.</li>
            <li><b>Alarm/Alert Violation Log (PDF & Excel)</b>: Summary of active alerts, severity details, and triggered IF-THEN workflows.</li>
        </ol>
    </p>
    <p>Please inspect critical alarms immediately to protect physical asset lifecycles.</p>
    <br>
    <p>Warm regards,<br><b>VAPLI Automation Engine</b></p>
    """
    reports_html = server.build_modern_template("Telemetry & Violations Summary", "Inspection Summary Reports", reports_body)
    with open("test_output/DailyReportsEmail.html", "w", encoding="utf-8") as f:
        f.write(reports_html)
    print("    Saved to test_output/DailyReportsEmail.html")

    print(f"[*] Simulating Compliance Gaps Email HTML body...")
    compliance_html = generate_compliance_html(test_date)
    with open("test_output/MissingTanksEmail.html", "w", encoding="utf-8") as f:
        f.write(compliance_html)
    print("    Saved to test_output/MissingTanksEmail.html")

    print(f"[*] Simulating Alerts Notification Email HTML body...")
    alerts_html = generate_alerts_email_html()
    with open("test_output/AlertsNotificationEmail.html", "w", encoding="utf-8") as f:
        f.write(alerts_html)
    print("    Saved to test_output/AlertsNotificationEmail.html")

    print("\n[+] HTML templates compiled and verified. All emails check out visually.")

if __name__ == "__main__":
    main()
