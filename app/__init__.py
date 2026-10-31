import os
import sqlite3
import time
from datetime import date
from pathlib import Path

from flask import Flask, abort, redirect, render_template, request, url_for
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

REQUESTS = Counter('stratego_http_requests_total', 'HTTP requests', ['method', 'endpoint', 'status'])
LATENCY = Histogram('stratego_http_request_duration_seconds', 'HTTP request duration', ['endpoint'])


def create_app(config=None):
    app = Flask(__name__)
    app.config.update(DATABASE=os.environ.get('DATABASE_PATH', 'data/stratego.db'))
    if config:
        app.config.update(config)
    Path(app.config['DATABASE']).parent.mkdir(parents=True, exist_ok=True)

    def db():
        connection = sqlite3.connect(app.config['DATABASE'], timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    with db() as connection:
        connection.execute('CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT "", due_date TEXT, status TEXT NOT NULL DEFAULT "todo" CHECK(status IN ("todo", "doing", "done")))')

    @app.before_request
    def start_timer():
        request.start_time = time.monotonic()

    @app.after_request
    def record_metrics(response):
        if request.endpoint != 'metrics':
            endpoint = request.endpoint or 'unknown'
            REQUESTS.labels(request.method, endpoint, response.status_code).inc()
            LATENCY.labels(endpoint).observe(time.monotonic() - request.start_time)
        return response

    @app.get('/')
    def index():
        status = request.args.get('status', 'all')
        if status not in ('all', 'todo', 'doing', 'done'):
            abort(400)
        with db() as connection:
            tasks = connection.execute('SELECT * FROM tasks' + (' WHERE status = ?' if status != 'all' else " WHERE status != 'done'") + ' ORDER BY due_date IS NULL, due_date, id DESC', (status,) if status != 'all' else ()).fetchall()
        today = date.today()
        def reminder(task):
            if not task['due_date'] or task['status'] == 'done':
                return ''
            days = (date.fromisoformat(task['due_date']) - today).days
            return 'Overdue' if days < 0 else 'Due today' if days == 0 else 'Due soon' if days <= 3 else 'Upcoming'
        return render_template('index.html', tasks=tasks, status=status, reminder=reminder)

    @app.post('/tasks')
    def create_task():
        title, description, due, status = validate()
        with db() as connection:
            connection.execute('INSERT INTO tasks(title, description, due_date, status) VALUES(?,?,?,?)', (title, description, due, status))
        return redirect(url_for('index'))

    def validate():
        title = request.form.get('title', '').strip()
        description = request.form.get('description', '').strip()
        due = request.form.get('due_date', '').strip() or None
        status = request.form.get('status', 'todo')
        if not title or len(title) > 200 or len(description) > 2000 or status not in ('todo', 'doing', 'done'):
            abort(400)
        if due:
            try:
                date.fromisoformat(due)
            except ValueError:
                abort(400)
        return title, description, due, status

    @app.post('/tasks/<int:task_id>/edit')
    def edit_task(task_id):
        values = validate()
        with db() as connection:
            cursor = connection.execute('UPDATE tasks SET title=?, description=?, due_date=?, status=? WHERE id=?', (*values, task_id))
            if not cursor.rowcount:
                abort(404)
        return redirect(url_for('index'))

    @app.post('/tasks/<int:task_id>/delete')
    def delete_task(task_id):
        with db() as connection:
            cursor = connection.execute('DELETE FROM tasks WHERE id=?', (task_id,))
            if not cursor.rowcount:
                abort(404)
        return redirect(url_for('index'))

    @app.get('/healthz')
    def health():
        with db() as connection:
            connection.execute('SELECT 1')
        return {'status': 'ok'}

    @app.get('/metrics')
    def metrics():
        return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

    return app
