extends Node

const DEFAULT_BASE_URL := "http://127.0.0.1:8787"
const DEFAULT_WORLD_ID := "poc1-world"

var base_url: String = DEFAULT_BASE_URL

func set_base_url(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")

func get_default_world_id() -> String:
	return DEFAULT_WORLD_ID

func post_events_batch(world_id: String, events: Array) -> Dictionary:
	var payload = {"events": events}
	return await _post_json("/v1/worlds/%s/events:batch" % world_id.uri_encode(), payload)

func pull_actions(world_id: String) -> Dictionary:
	return await _post_json("/v1/worlds/%s/actions/pull" % world_id.uri_encode(), {})

func _post_json(path: String, payload: Dictionary) -> Dictionary:
	var normalized_base = base_url.strip_edges().trim_suffix("/")
	if normalized_base.is_empty():
		normalized_base = DEFAULT_BASE_URL

	var url = normalized_base + path
	var request := HTTPRequest.new()
	add_child(request)

	var request_body = JSON.stringify(payload)
	var error = request.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		request_body
	)
	if error != OK:
		request.queue_free()
		return {
			"ok": false,
			"error": "request_error_%s" % error,
			"status": -1,
			"data": {}
		}

	var result_data = await request.request_completed
	request.queue_free()

	var result = result_data[0]
	var response_code = result_data[1]
	var body: PackedByteArray = result_data[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error": "http_result_%s" % result,
			"status": response_code,
			"data": {}
		}

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var payload_data := {}
	if parsed is Dictionary:
		payload_data = parsed

	return {
		"ok": response_code >= 200 and response_code < 300,
		"status": response_code,
		"data": payload_data
	}
