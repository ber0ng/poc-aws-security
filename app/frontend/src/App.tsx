import { useState, useEffect } from "react";
import axios from "axios";
import "./App.css";

interface Task {
  id: string;
  title: string;
  done: boolean;
}

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:3000";

function App() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [newTask, setNewTask] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let cancelled = false;

    axios
      .get(`${API_URL}/api/tasks`)
      .then((res) => {
        if (cancelled) return;
        setTasks(res.data.tasks);
        setLoading(false);
      })
      .catch(() => {
        if (cancelled) return;
        setError("Failed to fetch tasks");
        setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const addTask = async () => {
    if (!newTask.trim()) return;
    try {
      const res = await axios.post(`${API_URL}/api/tasks`, { title: newTask });
      setTasks([...tasks, res.data]);
      setNewTask("");
    } catch {
      setError("Failed to add task");
    }
  };

  return (
    <div className="container">
      <h1>AWS Security POC</h1>
      <p className="subtitle">Task Manager — Running on ECS Fargate</p>

      <div className="add-task">
        <input
          type="text"
          placeholder="Add a new task..."
          value={newTask}
          onChange={(e) => setNewTask(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && addTask()}
        />
        <button onClick={addTask}>Add</button>
      </div>

      {error && <p className="error">{error}</p>}

      {loading ? (
        <p>Loading tasks...</p>
      ) : (
        <ul className="task-list">
          {tasks.map((task) => (
            <li key={task.id} className={task.done ? "done" : ""}>
              <span>{task.done ? "✅" : "⬜"}</span>
              <span>{task.title}</span>
            </li>
          ))}
        </ul>
      )}

      <div className="info">
        <p>Infrastructure: AWS ECS Fargate</p>
        <p>Secrets: AWS Secrets Manager + KMS</p>
        <p>Monitoring: GuardDuty + Security Hub</p>
      </div>
    </div>
  );
}

export default App;
