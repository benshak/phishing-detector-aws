"""Web interface: upload or paste an email, see the verdict and recent history."""

import logging
from flask import Flask, render_template, request
from detector import analyze, parse_email
from db import init_db, save_check, recent_checks, sender_flagged_before

# Each check is logged; on AWS these logs are shipped to CloudWatch.
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

app = Flask(__name__)
init_db()


@app.route("/", methods=["GET", "POST"])
def index():
    """Show the form; on submit, analyze the email and save the result."""
    result = None
    if request.method == "POST":
        uploaded = request.files.get("email_file")
        if uploaded and uploaded.filename:
            text = uploaded.read().decode("utf-8", errors="replace")
        else:
            text = request.form.get("email_text", "")
        if text.strip():
            sender = parse_email(text)["sender"]
            result = analyze(text, flagged_before=sender_flagged_before(sender))
            save_check(result)
            logging.info(
                "Checked email from %s: score=%s verdict=%s",
                result["sender"],
                result["score"],
                result["verdict"],
            )
    return render_template("index.html", result=result, history=recent_checks())


@app.route("/health")
def health():
    """Health check endpoint used by the load balancer."""
    return "ok"


if __name__ == "__main__":
    app.run(debug=True)
