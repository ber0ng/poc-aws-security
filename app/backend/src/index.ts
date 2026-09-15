import express from 'express';
import cors from 'cors';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'healthy', service: 'backend' });
});

// Tasks routes
app.get('/api/tasks', (req, res) => {
    res.status(200).json({
        tasks: [
            { id: '1', title: 'Setup AWS Security POC', done: true },
            { id: '2', title: 'Configure GuardDuty', done: false },
            { id: '3', title: 'Setup Audit Manager', done: false },
        ]
    });
});

app.post('/api/tasks', (req, res) => {
    const { title } = req.body;
    if (!title) {
        return res.status(400).json({ error: 'Title is required' });
    }
    res.status(201).json({
        id: Math.random().toString(36).substr(2, 9),
        title,
        done: false
    });
});

app.listen(PORT, () => {
    console.log(`Backend running on port ${PORT}`);
});

export default app;