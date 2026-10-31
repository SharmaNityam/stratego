import pytest
from app import create_app


@pytest.fixture
def client(tmp_path):
    app = create_app({'TESTING': True, 'DATABASE': str(tmp_path / 'test.db')})
    return app.test_client()


def test_task_lifecycle_and_filter(client):
    assert client.post('/tasks', data={'title': 'First', 'due_date': '2000-01-01'}).status_code == 302
    assert b'Overdue' in client.get('/').data
    assert b'First' in client.get('/?status=todo').data
    assert b'First' not in client.get('/?status=done').data
    assert client.post('/tasks/1/edit', data={'title': 'Updated', 'status': 'done'}).status_code == 302
    assert b'Updated' in client.get('/?status=done').data
    assert client.post('/tasks/1/delete').status_code == 302
    assert b'Updated' not in client.get('/').data


def test_validation_and_missing_tasks(client):
    assert client.post('/tasks', data={'title': ''}).status_code == 400
    assert client.post('/tasks', data={'title': 'Task', 'due_date': 'bad'}).status_code == 400
    assert client.post('/tasks/999/delete').status_code == 404
    assert client.get('/?status=bad').status_code == 400


def test_health_and_metrics(client):
    assert client.get('/healthz').json == {'status': 'ok'}
    assert b'stratego_http_requests_total' in client.get('/metrics').data
