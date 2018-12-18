# Slack resources

We create JSON schemas from Slack document and api examples.

# Event api

Most event api examples are not wrapped meta data. But some examples are already wrapped. (e.x. `token_revoked` )

Our JSON schema did not include wrapping meta data.

```json
{
        "token": "XXYYZZ",
        "team_id": "TXXXXXXXX",
        "api_app_id": "AXXXXXXXXX",
        "event": {}, // Examples are inserted here.
        "type": "event_callback",
        "authed_users": [
                "UXXXXXXX1",
                "UXXXXXXX2"
        ],
        "event_id": "Ev08MFMKH6",
        "event_time": 1234567890
}
```

