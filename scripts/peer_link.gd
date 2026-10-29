extends RefCounted
## LAN-only direct WebRTC channels. No TURN relay or gameplay WebSocket fallback.
signal signal_out(data: Dictionary)
signal packet_received(packet: Dictionary)
signal opened
signal failed

var connection: WebRTCPeerConnection
var state_channel: WebRTCDataChannel
var control_channel: WebRTCDataChannel
var ready = false
var elapsed = 0.0
var interrupted = 0.0
var reported_failure = false
var sent_packets = 0
var received_packets = 0
var sent_bytes = 0
var received_bytes = 0
var last_state_bytes = 0
var skipped_realtime = 0
var coalesced_states = 0
var state_version = 1
const CODEC = preload("res://scripts/state_codec.gd")

func start(host: bool) -> void:
	close()
	if not OS.has_feature("web"):
		failed.emit()
		return
	connection = WebRTCPeerConnection.new()
	connection.session_description_created.connect(func(kind: String, sdp: String):
		if connection == null: return
		connection.set_local_description(kind,sdp)
		signal_out.emit({"kind":kind,"sdp":sdp}))
	connection.ice_candidate_created.connect(func(media: String,index: int,candidate: String):
		signal_out.emit({"kind":"candidate","media":media,"index":index,"candidate":candidate}))
	if connection.initialize({"iceServers":[]}) != OK:
		failed.emit()
		return
	state_channel = connection.create_data_channel("state",{"negotiated":true,"id":0,"ordered":false,"maxRetransmits":0})
	control_channel = connection.create_data_channel("controls",{"negotiated":true,"id":1,"ordered":true})
	if state_channel == null or control_channel == null:
		failed.emit()
		return
	if host and connection.create_offer() != OK: failed.emit()

func receive_signal(data: Dictionary) -> void:
	if connection == null: return
	match str(data.get("kind","")):
		"offer","answer": connection.set_remote_description(str(data.kind),str(data.sdp))
		"candidate": connection.add_ice_candidate(str(data.media),int(data.index),str(data.candidate))

func send(packet: Dictionary) -> bool:
	if not ready: return false
	var realtime = (packet.type=="state" and packet.get("phase","")!="end") or (packet.type=="input" and packet.get("action","")=="move")
	var channel = state_channel if realtime else control_channel
	if channel.get_ready_state()!=WebRTCDataChannel.STATE_OPEN: return false
	# Never build a FIFO of obsolete positions behind a congested connection.
	# The next tick sends a fresh independent snapshot once the channel drains.
	if realtime and channel.get_buffered_amount()>0:
		skipped_realtime += 1
		return false
	if not realtime and channel.get_buffered_amount()>65536: return false
	var bytes = CODEC.encode(packet,state_version) if packet.type=="state" else JSON.stringify(packet).to_utf8_buffer()
	if packet.type=="state": last_state_bytes = bytes.size()
	if channel.put_packet(bytes) == OK:
		sent_packets += 1
		sent_bytes += bytes.size()
		return true
	return false

func poll(dt: float) -> void:
	if connection == null or reported_failure: return
	connection.poll()
	elapsed += dt
	var connected = state_channel != null and control_channel != null and state_channel.get_ready_state()==WebRTCDataChannel.STATE_OPEN and control_channel.get_ready_state()==WebRTCDataChannel.STATE_OPEN
	if connected:
		interrupted = 0
		if not ready:
			ready = true
			send({"type":"codec","version":CODEC.VERSION})
			opened.emit()
		for channel in [control_channel,state_channel]:
			var recent_states: Array[PackedByteArray] = []
			while channel != null and channel.get_available_packet_count()>0:
				var bytes = channel.get_packet()
				received_bytes += bytes.size()
				if channel==state_channel and CODEC.sequence(bytes)>=0:
					received_packets += 1
					coalesced_states += retain_latest(recent_states,bytes)
					continue
				var packet = CODEC.decode(bytes) if not bytes.is_empty() and bytes[0]==186 else JSON.parse_string(bytes.get_string_from_utf8())
				if packet is Dictionary and not packet.is_empty():
					if packet.get("type","")=="codec":
						state_version=clampi(int(packet.get("version",1)),1,CODEC.VERSION)
						continue
					received_packets += 1
					packet_received.emit(packet)
			# Keep just the two newest frames needed for interpolation this tick.
			# Decode them only after draining, avoiding pose allocations for old frames.
			for bytes in recent_states:
				var packet = CODEC.decode(bytes)
				if not packet.is_empty(): packet_received.emit(packet)
	else:
		interrupted += dt
		if (not ready and elapsed>20) or (ready and interrupted>12):
			reported_failure = true
			failed.emit()

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
	if connection != null: connection.close()
	connection = null
	state_channel = null
	control_channel = null
	ready = false
	state_version = 1
	elapsed = 0
	interrupted = 0
	reported_failure = false
	sent_packets = 0
	received_packets = 0
	sent_bytes = 0
	received_bytes = 0
	last_state_bytes = 0
	skipped_realtime = 0
	coalesced_states = 0
