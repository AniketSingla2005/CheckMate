#!/bin/bash

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "dialog package is not installed. Installing..."
    sudo apt-get update && sudo apt-get install -y dialog || {
        echo "Failed to install dialog. Please install it manually and try again."
        exit 1
    }
fi

# Check if script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo or as root"
    exit 1
fi

# Global variables
DATA_DIR="/var/lib/attendance_tracker"
STUDENTS_FILE="$DATA_DIR/students.csv"
ATTENDANCE_DIR="$DATA_DIR/attendance"
LOG_FILE="$DATA_DIR/attendance.log"
TEMP_FILE="/tmp/attendance_temp.$$"
DIALOG_HEIGHT=20
DIALOG_WIDTH=70

# Function to log actions
log_action() {
    local action="$1"
    local details="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $action: $details" >> "$LOG_FILE"
}

# Function to create required directories and files
initialize_system() {
    # Create data directory if it doesn't exist
    if [ ! -d "$DATA_DIR" ]; then
        mkdir -p "$DATA_DIR"
        chmod 750 "$DATA_DIR"
    fi

    # Create attendance directory if it doesn't exist
    if [ ! -d "$ATTENDANCE_DIR" ]; then
        mkdir -p "$ATTENDANCE_DIR"
        chmod 750 "$ATTENDANCE_DIR"
    fi

    # Create students file if it doesn't exist
    if [ ! -f "$STUDENTS_FILE" ]; then
        echo "id,name,email,class" > "$STUDENTS_FILE"
        chmod 640 "$STUDENTS_FILE"
    fi

    # Create log file if it doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        chmod 640 "$LOG_FILE"
    fi

    log_action "System" "Initialized attendance tracker system"
}

# Function to display error message
show_error() {
    local message="$1"
    dialog --title "Error" --msgbox "$message" 8 50
    log_action "Error" "$message"
}

# Function to show success message
show_success() {
    local message="$1"
    dialog --title "Success" --msgbox "$message" 8 50
    log_action "Success" "$message"
}

# Function to validate student ID (alphanumeric)
validate_student_id() {
    local id="$1"
    if [[ ! "$id" =~ ^[A-Za-z0-9]+$ ]]; then
        return 1
    fi
    return 0
}

# Function to validate email format
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Function to check if student ID already exists
student_exists() {
    local id="$1"
    grep -q "^$id," "$STUDENTS_FILE"
    return $?
}

# Function to add a new student
add_student() {
    # Form for adding a new student
    dialog --title "Add New Student" \
           --form "Enter student details:" \
           $DIALOG_HEIGHT $DIALOG_WIDTH 4 \
           "Student ID:"    1 1 "" 1 20 20 0 \
           "Name:"          2 1 "" 2 20 30 0 \
           "Email:"         3 1 "" 3 20 30 0 \
           "Class:"         4 1 "" 4 20 20 0 \
           2> "$TEMP_FILE"

    # Check if user cancelled
    if [ $? -ne 0 ]; then
        rm -f "$TEMP_FILE"
        return
    fi

    # Read form values
    local id=$(sed -n '1p' "$TEMP_FILE")
    local name=$(sed -n '2p' "$TEMP_FILE")
    local email=$(sed -n '3p' "$TEMP_FILE")
    local class=$(sed -n '4p' "$TEMP_FILE")
    rm -f "$TEMP_FILE"

    # Validate input
    if [ -z "$id" ] || [ -z "$name" ] || [ -z "$email" ] || [ -z "$class" ]; then
        show_error "All fields are required"
        return
    fi

    # Validate student ID
    if ! validate_student_id "$id"; then
        show_error "Invalid Student ID format. Use only alphanumeric characters."
        return
    fi

    # Validate email
    if ! validate_email "$email"; then
        show_error "Invalid email format"
        return
    fi

    # Check if student already exists
    if student_exists "$id"; then
        show_error "Student with ID '$id' already exists"
        return
    fi

    # Add student to file
    echo "$id,$name,$email,$class" >> "$STUDENTS_FILE"
    
    # Log action
    log_action "Add Student" "Added student $id: $name ($class)"
    
    show_success "Student '$name' has been added successfully"
}
