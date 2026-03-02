# Create admin and test users for ICMS Inspection app
puts "Creating users..."
puts "=" * 50

users_to_create = [
  {
    email: 'admin@icms.com',
    password: 'Admin_4312!',
    role: :admin,
    description: 'Admin user'
  },
  {
    email: 'tester@icms.com',
    password: 'Tester_4312!',
    role: :inspector,
    description: 'Test user (Inspector)'
  }
]

created_users = []
errors = []

users_to_create.each do |user_data|
  user = User.find_or_create_by(email: user_data[:email]) do |u|
    u.password = user_data[:password]
    u.password_confirmation = user_data[:password]
    u.role = user_data[:role]
  end

  if user.persisted?
    created_users << user
    puts "✓ #{user_data[:description]} created successfully!"
    puts "  Email: #{user.email}"
    puts "  Role: #{user.role}"
    puts ""
  else
    errors << "✗ Error creating #{user_data[:description]}: #{user.errors.full_messages.join(', ')}"
  end
end

puts "=" * 50
puts "Summary:"
puts "  Created: #{created_users.count} user(s)"
puts "  Errors: #{errors.count}" if errors.any?
puts ""

if created_users.any?
  puts "Login credentials:"
  puts "-" * 50
  users_to_create.each do |user_data|
    puts "#{user_data[:description]}:"
    puts "  Email: #{user_data[:email]}"
    puts "  Password: #{user_data[:password]}"
    puts ""
  end
end

if errors.any?
  puts "Errors encountered:"
  errors.each { |error| puts error }
  exit 1
end

puts "✓ All users created successfully!"