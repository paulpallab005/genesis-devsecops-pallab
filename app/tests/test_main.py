"""
Unit tests for Genesis Events API.

Tests all three endpoints with comprehensive coverage:
- GET /health
- POST /events
- GET /events/{id}

Target: >75% code coverage

Note: Tests ignore planted security flaws (hardcoded password, raw logging)
as these are intentional for pipeline security gate demonstration.
"""

import os
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock

# Set test environment before importing main
os.environ['ENVIRONMENT'] =  'test'

from main import app, events_store


@pytest.fixture
def client():
    """Create a test client."""
    return TestClient(app)


@pytest.fixture(autouse=True)
def clear_events_store():
    """Clear events store before each test."""
    events_store.clear()
    yield
    events_store.clear()


class TestHealthEndpoint:
    """Tests for the /health endpoint."""
    
    def test_health_check_success(self, client):
        """Test health check returns OK status."""
        response = client.get("/health")
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["version"] == "1.0.0"
        assert data["env"] == "test"
    
    def test_health_check_structure(self, client):
        """Test health check response structure."""
        response = client.get("/health")
        data = response.json()
        
        assert "status" in data
        assert "version" in data
        assert "env" in data


class TestCreateEventEndpoint:
    """Tests for POST /events endpoint."""
    
    def test_create_event_success(self, client):
        """Test creating a valid event."""
        event_data = {
            "event_type": "user_signup",
            "description": "User registered successfully",
            "metadata": {"source": "web"}
        }
        
        with patch('main.emit_custom_metric') as mock_metric:
            response = client.post("/events", json=event_data)
        
        assert response.status_code == 201
        data = response.json()
        
        assert "id" in data
        assert data["event_type"] == "user_signup"
        assert data["description"] == "User registered successfully"
        assert data["metadata"] == {"source": "web"}
        assert "created_at" in data
        
        # Verify metric was emitted
        mock_metric.assert_called_once()
    
    def test_create_event_without_metadata(self, client):
        """Test creating event without optional metadata."""
        event_data = {
            "event_type": "system_alert",
            "description": "System health check failed"
        }
        
        with patch('main.emit_custom_metric'):
            response = client.post("/events", json=event_data)
        
        assert response.status_code == 201
        data = response.json()
        
        assert data["event_type"] == "system_alert"
        assert data["metadata"] is None
    
    def test_create_event_missing_required_field(self, client):
        """Test creating event with missing required field."""
        event_data = {
            "event_type": "incomplete_event"
            # Missing 'description' field
        }
        
        response = client.post("/events", json=event_data)
        
        assert response.status_code == 422  # Validation error
    
    def test_create_event_invalid_type(self, client):
        """Test creating event with invalid data types."""
        event_data = {
            "event_type": 12345,  # Should be string
            "description": "Invalid event type"
        }
        
        response = client.post("/events", json=event_data)
        
        assert response.status_code == 422
    
    def test_create_event_empty_type(self, client):
        """Test creating event with empty event_type."""
        event_data = {
            "event_type": "",  # Empty string should fail
            "description": "Event with empty type"
        }
        
        response = client.post("/events", json=event_data)
        
        assert response.status_code == 422
    
    def test_create_event_too_long_description(self, client):
        """Test creating event with description exceeding max length."""
        event_data = {
            "event_type": "long_description",
            "description": "x" * 501  # Max is 500
        }
        
        response = client.post("/events", json=event_data)
        
        assert response.status_code == 422
    
    def test_create_multiple_events(self, client):
        """Test creating multiple events."""
        with patch('main.emit_custom_metric'):
            response1 = client.post("/events", json={
                "event_type": "type1",
                "description": "First event"
            })
            response2 = client.post("/events", json={
                "event_type": "type2",
                "description": "Second event"
            })
        
        assert response1.status_code == 201
        assert response2.status_code == 201
        
        # Verify different IDs
        assert response1.json()["id"] != response2.json()["id"]


class TestGetEventEndpoint:
    """Tests for GET /events/{id} endpoint."""
    
    def test_get_event_success(self, client):
        """Test retrieving an existing event."""
        # Create an event first
        with patch('main.emit_custom_metric'):
            create_response = client.post("/events", json={
                "event_type": "test_event",
                "description": "Test event for retrieval"
            })
        
        event_id = create_response.json()["id"]
        
        # Retrieve the event
        response = client.get(f"/events/{event_id}")
        
        assert response.status_code == 200
        data = response.json()
        
        assert data["id"] == event_id
        assert data["event_type"] == "test_event"
        assert data["description"] == "Test event for retrieval"
    
    def test_get_event_not_found(self, client):
        """Test retrieving a non-existent event."""
        fake_id = "00000000-0000-0000-0000-000000000000"
        
        response = client.get(f"/events/{fake_id}")
        
        assert response.status_code == 404
        data = response.json()
        
        assert "detail" in data
        assert data["detail"]["error"] == "Event not found"
        assert data["detail"]["event_id"] == fake_id
    
    def test_get_event_with_metadata(self, client):
        """Test retrieving event that has metadata."""
        with patch('main.emit_custom_metric'):
            create_response = client.post("/events", json={
                "event_type": "payment",
                "description": "Payment processed",
                "metadata": {"amount": "100", "currency": "USD"}
            })
        
        event_id = create_response.json()["id"]
        response = client.get(f"/events/{event_id}")
        
        assert response.status_code == 200
        data = response.json()
        
        assert data["metadata"] == {"amount": "100", "currency": "USD"}


class TestRootEndpoint:
    """Tests for the root endpoint."""
    
    def test_root_endpoint(self, client):
        """Test root endpoint returns API information."""
        response = client.get("/")
        
        assert response.status_code == 200
        data = response.json()
        
        assert data["name"] == "Genesis Events API"
        assert data["version"] == "1.0.0"
        assert "docs" in data
        assert "health" in data


class TestUtilityFunctions:
    """Tests for utility functions."""
    
    @patch('main.boto3.client')
    def test_get_secret_success(self, mock_boto_client):
        """Test successful secret retrieval."""
        from main import get_secret
        
        # Mock Secrets Manager response
        mock_client = MagicMock()
        mock_client.get_secret_value.return_value = {
            'SecretString': 'my-secret-value'
        }
        mock_boto_client.return_value = mock_client
        
        # Reset the global client
        import main
        main._secrets_client = None
        
        secret = get_secret('test-secret')
        
        assert secret == 'my-secret-value'
        mock_client.get_secret_value.assert_called_once_with(SecretId='test-secret')
    
    @patch('main.boto3.client')
    def test_get_secret_local_fallback(self, mock_boto_client):
        """Test secret retrieval falls back to dummy in local environment."""
        from main import get_secret
        from botocore.exceptions import ClientError
        
        # Mock Secrets Manager to raise ClientError
        mock_client = MagicMock()
        error_response = {'Error': {'Code': 'ResourceNotFoundException', 'Message': 'Secret not found'}}
        mock_client.get_secret_value.side_effect = ClientError(error_response, 'GetSecretValue')
        mock_boto_client.return_value = mock_client
        
        # Reset the global client
        import main
        main._secrets_client = None
        
        # Set environment to local
        os.environ['ENVIRONMENT'] = 'local'
        
        secret = get_secret('test-secret')
        
        assert secret == 'local-dummy-secret'
        
        # Reset environment
        os.environ['ENVIRONMENT'] = 'test'
    
    @patch('main.boto3.client')
    def test_emit_custom_metric_success(self, mock_boto_client):
        """Test successful metric emission."""
        from main import emit_custom_metric
        
        # Mock CloudWatch response
        mock_client = MagicMock()
        mock_boto_client.return_value = mock_client
        
        # Reset the global client
        import main
        main._cloudwatch_client = None
        
        emit_custom_metric('TestMetric', 1.0, {'Environment': 'test'})
        
        # Verify put_metric_data was called
        assert mock_client.put_metric_data.called
    
    @patch('main.boto3.client')
    def test_emit_custom_metric_handles_error(self, mock_boto_client):
        """Test metric emission handles errors gracefully."""
        from main import emit_custom_metric
        
        # Mock CloudWatch to raise exception
        mock_client = MagicMock()
        mock_client.put_metric_data.side_effect = Exception("CloudWatch error")
        mock_boto_client.return_value = mock_client
        
        # Reset the global client
        import main
        main._cloudwatch_client = None
        
        # Should not raise exception
        emit_custom_metric('TestMetric', 1.0)


# Test coverage summary
def test_coverage_placeholder():
    """Placeholder to ensure pytest runs even if other tests are skipped."""
    assert True
