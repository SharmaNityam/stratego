import pytest
from app import create_app


@pytest.fixture
def client(tmp_path):
    app = create_app({'TESTING': True, 'DATABASE': str(tmp_path / 'test.db'), 'DATABASE_URL': None})
    return app.test_client()


def test_task_lifecycle_and_filter(client):
    assert client.post('/tasks', data={'title': 'First', 'due_date': '2000-01-01', 'priority': 'high'}).status_code == 302
    assert b'Overdue' in client.get('/').data
    assert b'First' in client.get('/?status=todo').data
    assert b'First' not in client.get('/?status=done').data
    assert client.post('/tasks/1/edit', data={'title': 'Updated', 'status': 'done', 'priority': 'high'}).status_code == 302
    assert b'Updated' in client.get('/?status=done').data
    assert b'Updated' not in client.get('/').data
    assert client.post('/tasks/1/delete').status_code == 302
    assert b'Updated' not in client.get('/').data


def test_validation_and_missing_tasks(client):
    assert client.post('/tasks', data={'title': ''}).status_code == 400
    assert client.post('/tasks', data={'title': 'Task', 'due_date': 'bad', 'priority': 'low'}).status_code == 400
    assert client.post('/tasks/999/delete').status_code == 404
    assert client.get('/?status=bad').status_code == 400


def test_health_and_metrics(client):
    assert client.get('/healthz').json == {'status': 'ok'}
    assert b'stratego_http_requests_total' in client.get('/metrics').data


def test_reminder_categories_and_completed_task(client):
    from datetime import date, timedelta

    today = date.today()
    for title, days, status in [
        ('Overdue task', -1, 'todo'),
        ('Today task', 0, 'todo'),
        ('Soon task', 2, 'doing'),
        ('Upcoming task', 7, 'todo'),
        ('Completed task', -1, 'done'),
    ]:
        response = client.post('/tasks', data={
            'title': title,
            'due_date': (today + timedelta(days=days)).isoformat(),
            'status': status,
            'priority': 'medium',
        })
        assert response.status_code == 302
    page = client.get('/').data.decode()
    assert 'Overdue' in page
    assert 'Due today' in page
    assert 'Due soon' in page
    assert 'Upcoming' in page
    assert page.count('<span>Overdue ·') == 1
    assert 'Completed task' not in page
    assert 'Completed task' in client.get('/?status=done').data.decode()
    assert "return confirm('Delete this task?')" in page


def test_priority_required_and_urgency_sort(client):
    assert client.post('/tasks', data={'title': 'Missing priority'}).status_code == 400
    for title, due, priority in [('Low', '2030-01-01', 'low'), ('High', '2030-01-01', 'high'), ('Earlier', '2020-01-01', 'low')]:
        assert client.post('/tasks', data={'title': title, 'due_date': due, 'priority': priority}).status_code == 302
    page = client.get('/?sort=urgency').data.decode()
    assert page.index('value="Earlier"') < page.index('value="High"') < page.index('value="Low"')
    assert client.get('/?sort=invalid').status_code == 400


def test_existing_sqlite_tasks_get_a_priority(tmp_path):
    import sqlite3

    database = tmp_path / 'old.db'
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', due_date TEXT, status TEXT NOT NULL DEFAULT 'todo')")
        connection.execute("INSERT INTO tasks(title) VALUES ('Existing')")
    app = create_app({'TESTING': True, 'DATABASE': str(database), 'DATABASE_URL': None})
    page = app.test_client().get('/').data.decode()
    assert 'Existing' in page
    assert 'value="medium" selected' in page


def test_postgres_integration_when_available():
    import os

    url = os.environ.get('TEST_DATABASE_URL')
    if not url:
        pytest.skip('Set TEST_DATABASE_URL to run PostgreSQL integration')
    app = create_app({'TESTING': True, 'DATABASE_URL': url})
    client = app.test_client()
    assert client.get('/healthz').status_code == 200
    assert client.post('/tasks', data={'title': 'PostgreSQL integration', 'priority': 'high'}).status_code == 302
    assert b'PostgreSQL integration' in client.get('/').data
