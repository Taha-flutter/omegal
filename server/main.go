package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Client struct {
	conn     *websocket.Conn
	username string
	roomID   string
	matched  bool
}

type Room struct {
	ID      string
	Clients []*Client
}

var (
	clients     = make(map[*websocket.Conn]*Client)
	waitingRoom = make([]*Client, 0)
	rooms       = make(map[string]*Room)
	mu          sync.RWMutex
)

type Message struct {
	Type     string `json:"type"`
	Username string `json:"username,omitempty"`
	RoomID   string `json:"room_id,omitempty"`
	Data     string `json:"data,omitempty"`
}

func main() {
	http.HandleFunc("/ws", handleConnections)

	fmt.Println("Server started at :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func handleConnections(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Fatal(err)
	}
	defer ws.Close()

	// Create new client
	client := &Client{
		conn:     ws,
		username: "",
		roomID:   "",
		matched:  false,
	}

	mu.Lock()
	clients[ws] = client
	mu.Unlock()

	log.Printf("New user connected. Total clients: %d", len(clients))

	// Send welcome message
	welcomeMsg := Message{Type: "connected"}
	sendMessage(ws, welcomeMsg)

	for {
		_, msgBytes, err := ws.ReadMessage()
		if err != nil {
			handleDisconnect(ws)
			break
		}

		var msg map[string]interface{}
		if err := json.Unmarshal(msgBytes, &msg); err != nil {
			log.Printf("Error parsing message: %v", err)
			continue
		}

		handleMessage(client, msg)
	}
}

func handleMessage(client *Client, msg map[string]interface{}) {
	log.Printf("Received message from %s: %+v", client.username, msg)

	msgType, ok := msg["type"].(string)
	if !ok {
		log.Printf("Invalid message type")
		return
	}

	switch msgType {
	case "join_waiting":
		if username, ok := msg["Username"].(string); ok {
			client.username = username
		}
		log.Printf("Processing join_waiting for user: %s", client.username)
		joinWaitingRoom(client)
	case "leave_waiting":
		log.Printf("Processing leave_waiting for user: %s", client.username)
		leaveWaitingRoom(client)
	case "sdp":
		// Forward WebRTC signaling to room partner
		forwardToRoomPartner(client, msg)
	case "candidate":
		// Forward WebRTC signaling to room partner
		forwardToRoomPartner(client, msg)
	case "end_call":
		endCall(client)
	default:
		log.Printf("Unknown message type: %s", msgType)
	}
}

func joinWaitingRoom(client *Client) {
	mu.Lock()
	defer mu.Unlock()

	// Check if client is already in waiting room
	for _, waitingClient := range waitingRoom {
		if waitingClient == client {
			return
		}
	}

	waitingRoom = append(waitingRoom, client)
	log.Printf("User %s joined waiting room. Waiting users: %d", client.username, len(waitingRoom))

	// Send waiting status
	statusMsg := Message{Type: "waiting", Data: fmt.Sprintf("Waiting for another user... (%d users waiting)", len(waitingRoom))}
	sendMessage(client.conn, statusMsg)

	// Try to match users
	tryMatchUsers()
}

func leaveWaitingRoom(client *Client) {
	mu.Lock()
	defer mu.Unlock()

	// Remove from waiting room
	for i, waitingClient := range waitingRoom {
		if waitingClient == client {
			waitingRoom = append(waitingRoom[:i], waitingRoom[i+1:]...)
			break
		}
	}

	log.Printf("User %s left waiting room. Waiting users: %d", client.username, len(waitingRoom))
}

func tryMatchUsers() {
	if len(waitingRoom) >= 2 {
		// Create a room with the first two users
		user1 := waitingRoom[0]
		user2 := waitingRoom[1]

		// Remove from waiting room
		waitingRoom = waitingRoom[2:]

		// Create room
		roomID := fmt.Sprintf("room_%d", len(rooms)+1)
		room := &Room{
			ID:      roomID,
			Clients: []*Client{user1, user2},
		}
		rooms[roomID] = room

		// Assign room to clients
		user1.roomID = roomID
		user2.roomID = roomID
		user1.matched = true
		user2.matched = true

		// Notify both users they are matched
		// First user becomes the caller
		matchMsg1 := Message{Type: "matched", RoomID: roomID, Data: "caller"}
		matchMsg2 := Message{Type: "matched", RoomID: roomID, Data: "answerer"}
		sendMessage(user1.conn, matchMsg1)
		sendMessage(user2.conn, matchMsg2)

		log.Printf("Matched users %s and %s in room %s", user1.username, user2.username, roomID)
	}
}

func forwardToRoomPartner(client *Client, msg map[string]interface{}) {
	mu.RLock()
	defer mu.RUnlock()

	if client.roomID == "" {
		return
	}

	room, exists := rooms[client.roomID]
	if !exists {
		return
	}

	// Find the partner
	for _, roomClient := range room.Clients {
		if roomClient != client {
			// Forward the message as-is to preserve SDP and ICE candidate structure
			msgBytes, err := json.Marshal(msg)
			if err != nil {
				log.Printf("Error marshaling forwarded message: %v", err)
				return
			}
			if err := roomClient.conn.WriteMessage(websocket.TextMessage, msgBytes); err != nil {
				log.Printf("Error forwarding message: %v", err)
			}
			break
		}
	}
}

func endCall(client *Client) {
	mu.Lock()
	defer mu.Unlock()

	if client.roomID == "" {
		return
	}

	room, exists := rooms[client.roomID]
	if !exists {
		return
	}

	// Notify partner that call ended
	for _, roomClient := range room.Clients {
		if roomClient != client {
			endMsg := Message{Type: "call_ended"}
			sendMessage(roomClient.conn, endMsg)
		}
	}

	// Remove room
	delete(rooms, client.roomID)

	// Reset client state
	client.roomID = ""
	client.matched = false

	log.Printf("Call ended for user %s", client.username)
}

func handleDisconnect(ws *websocket.Conn) {
	mu.Lock()
	defer mu.Unlock()

	client, exists := clients[ws]
	if !exists {
		return
	}

	// Remove from waiting room if present
	leaveWaitingRoom(client)

	// End call if in a room
	if client.roomID != "" {
		endCall(client)
	}

	// Remove client
	delete(clients, ws)

	log.Printf("User %s disconnected. Total clients: %d", client.username, len(clients))
}

func sendMessage(conn *websocket.Conn, msg Message) {
	msgBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Error marshaling message: %v", err)
		return
	}

	if err := conn.WriteMessage(websocket.TextMessage, msgBytes); err != nil {
		log.Printf("Error sending message: %v", err)
	}
}
