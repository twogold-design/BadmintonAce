extends RefCounted
## Match traffic uses the existing server WebSocket. No peer connections or UDP.
signal packet_received(packet: Dictionary)
signal opened
signal failed

const CODEC = preload("res://scripts/state_codec.gd")
var socket: WebSocketPeer
var ready = false
var sent_packets = 0
var received_packets = 0
var sent_bytes = 0
var received_bytes = 0
var last_state_bytes = 0
var skipped_realtime = 0
var coalesced_states = 0
var state_version = CODEC.VERSION
var recent_states: Array[PackedByteArray] = []

func start(server_socket: WebSocketPeer) -> void:
	close()
	socket = server_socket
	ready = socket != null and socket.get_ready_state()==WebSocketPeer.STATE_OPEN
	if ready: opened.emit()
	else: failed.emit()

func send(packet: Dictionary) -> bool:
	if not ready or socket == null or socket.get_ready_state()!=WebSocketPeer.STATE_OPEN: return false
	var realtime = (packet.type=="state" and packet.get("phase","")!="end") or (packet.type=="input" and packet.get("action","")=="move")
	# Skip replaceable positions under congestion; never queue seconds of old play.
	if realtime and socket.get_current_outbound_buffered_amount()>4096:
		skipped_realtime += 1
		return false
	if socket.get_current_outbound_buffered_amount()>262144:
		socket.close(1013,"Connection congested")
		return false
	var bytes = CODEC.encode(packet,state_version) if packet.type=="state" else JSON.stringify({"type":"relay","packet":packet}).to_utf8_buffer()
	if packet.type=="state": last_state_bytes = bytes.size()
	var result = socket.put_packet(bytes) if packet.type=="state" else socket.send_text(bytes.get_string_from_utf8())
	if result != OK: return false
	sent_packets += 1
	sent_bytes += bytes.size()
	return true

func receive_binary(bytes: PackedByteArray) -> void:
	if not ready or CODEC.sequence(bytes)<0: return
	received_packets += 1
	received_bytes += bytes.size()
	coalesced_states += retain_latest(recent_states,bytes)

func receive_packet(packet: Dictionary) -> void:
	if not ready: return
	flush_states()
	received_packets += 1
	received_bytes += JSON.stringify(packet).to_utf8_buffer().size()
	packet_received.emit(packet)

func flush_states() -> void:
	var frames = recent_states
	recent_states = []
	for bytes in frames:
		var packet = CODEC.decode(bytes)
		if not packet.is_empty(): packet_received.emit(packet)

func poll(_dt: float) -> void:
	flush_states()

static func retain_latest(recent: Array[PackedByteArray], bytes: PackedByteArray) -> int:
	var seq = CODEC.sequence(bytes)
	for existing in recent:
		if CODEC.sequence(existing)==seq: return 1
	recent.append(bytes)
	recent.sort_custom(func(a,b): return CODEC.sequence(a)<CODEC.sequence(b))
	if recent.size()>2:
		recent.pop_front()
		return 1
	return 0

func close() -> void:
	# The account socket belongs to main and remains open after a match.
	socket = null
	ready = false
	state_version = CODEC.VERSION
	recent_states.clear()
	sent_packets = 0
	received_packets = 0
	sent_bytes = 0
	received_bytes = 0
	last_state_bytes = 0
	skipped_realtime = 0
	coalesced_states = 0
