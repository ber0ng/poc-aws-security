output "service_name" {
  value = aws_ecs_service.ecs-service.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.main-task.arn
}

output "security_group_id" {
  value = aws_security_group.ecs-sg.id
}


