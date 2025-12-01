package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

var (
	version   = "dev"
	gitCommit = "unknown"
	buildTime = "unknown"
)

func main() {
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/version", handleVersion)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting server on port %s", port)
	log.Printf("Version: %s, Commit: %s, Built: %s", version, gitCommit, buildTime)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	html := fmt.Sprintf(`
<!DOCTYPE html>
<html>
<head>
    <title>CI/CD Demo App</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%%, #764ba2 100%%);
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            padding: 30px;
            backdrop-filter: blur(10px);
        }
        h1 {
            margin-top: 0;
        }
        .info {
            background: rgba(255, 255, 255, 0.2);
            padding: 15px;
            border-radius: 5px;
            margin: 10px 0;
        }
        .label {
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 CI/CD Demo Application</h1>
        <p>GitOps + ArgoCD + GitHub Actions デモアプリケーション</p>

        <div class="info">
            <div><span class="label">Version:</span> %s</div>
            <div><span class="label">Git Commit:</span> %s</div>
            <div><span class="label">Build Time:</span> %s</div>
            <div><span class="label">Current Time:</span> %s</div>
        </div>

        <h2>Endpoints:</h2>
        <ul>
            <li><a href="/" style="color: white;">/ - このページ</a></li>
            <li><a href="/health" style="color: white;">/health - ヘルスチェック</a></li>
            <li><a href="/version" style="color: white;">/version - バージョン情報（JSON）</a></li>
        </ul>
    </div>
</body>
</html>
`, version, gitCommit, buildTime, time.Now().Format("2006-01-02 15:04:05 MST"))

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, html)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "OK")
}

func handleVersion(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"version":"%s","gitCommit":"%s","buildTime":"%s"}`, version, gitCommit, buildTime)
}
