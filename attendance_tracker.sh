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

# Function to list all students
list_students() {
    # Create a temporary file for the student list
    local temp_list="/tmp/student_list.$$"
    
    # Create header for the list
    echo -e "ID\tNAME\tEMAIL\tCLASS" > "$temp_list"
    echo -e "------------------------------------------------------" >> "$temp_list"
    
    # Skip header line and format student data
    tail -n +2 "$STUDENTS_FILE" | sed 's/,/\t/g' >> "$temp_list"
    
    # Display the list using dialog
    dialog --title "Student List" --textbox "$temp_list" $DIALOG_HEIGHT $DIALOG_WIDTH
    
    # Clean up
    rm -f "$temp_list"
    
    # Log action
    log_action "List" "Viewed student list"
}

# Function to delete a student
delete_student() {
    # Create a temporary file for student choices
    local temp_choices="/tmp/student_choices.$$"
    
    # Generate list of students for selection
    echo -n "" > "$temp_choices"
    local line_num=1
    tail -n +2 "$STUDENTS_FILE" | while IFS=, read -r id name email class; do
        echo "$id \"$name ($class)\"" >> "$temp_choices"
        ((line_num++))
    done
    
    # Check if there are students to delete
    if [ ! -s "$temp_choices" ]; then
        show_error "No students found in the system"
        rm -f "$temp_choices"
        return
    fi
    
    # Display menu to select a student
    dialog --title "Delete Student" \
           --menu "Select a student to delete:" \
           $DIALOG_HEIGHT $DIALOG_WIDTH $((line_num > 10 ? 10 : line_num)) \
           --file "$temp_choices" \
           2> "$TEMP_FILE"
    
    # Check if user cancelled
    if [ $? -ne 0 ]; then
        rm -f "$temp_choices" "$TEMP_FILE"
        return
    fi
    
    # Get selected student ID
    local selected_id=$(cat "$TEMP_FILE")
    rm -f "$temp_choices" "$TEMP_FILE"
    
    # Confirm deletion
    dialog --title "Confirm Deletion" \
           --yesno "Are you sure you want to delete student with ID '$selected_id'?" \
           8 60
    
    # If confirmed, delete the student
    if [ $? -eq 0 ]; then
        # Get student name for logging
        local student_name=$(grep "^$selected_id," "$STUDENTS_FILE" | cut -d',' -f2)
        
        # Create a temporary file without the selected student
        grep -v "^$selected_id," "$STUDENTS_FILE" > "$TEMP_FILE"
        
        # Replace original file
        mv "$TEMP_FILE" "$STUDENTS_FILE"
        
        # Delete student attendance records
        if [ -f "$ATTENDANCE_DIR/$selected_id.csv" ]; then
            rm -f "$ATTENDANCE_DIR/$selected_id.csv"
        fi
        
        # Log action
        log_action "Delete" "Deleted student $selected_id: $student_name"
        
        show_success "Student with ID '$selected_id' has been deleted"
    fi
}

# Function to record attendance for a date
record_attendance() {
    # Ask for date (default to today)
    local default_date=$(date +"%Y-%m-%d")
    dialog --title "Record Attendance" \
           --inputbox "Enter date (YYYY-MM-DD) or leave blank for today:" \
           8 50 "$default_date" \
           2> "$TEMP_FILE"
    
    # Check if user cancelled
    if [ $? -ne 0 ]; then
        rm -f "$TEMP_FILE"
        return
    fi
    
    local selected_date=$(cat "$TEMP_FILE")
    rm -f "$TEMP_FILE"
    
    # Validate date format
    if [ -n "$selected_date" ] && ! date -d "$selected_date" >/dev/null 2>&1; then
        show_error "Invalid date format. Please use YYYY-MM-DD"
        return
    fi
    
    # If blank, use today's date
    if [ -z "$selected_date" ]; then
        selected_date="$default_date"
    fi
    
    # Create a checklist of students
    local temp_checklist="/tmp/attendance_checklist.$$"
    echo -n "" > "$temp_checklist"
    
    # Check if there are students
    if [ $(tail -n +2 "$STUDENTS_FILE" | wc -l) -eq 0 ]; then
        show_error "No students found in the system"
        rm -f "$temp_checklist"
        return
    fi
    
    # Generate student checklist
    tail -n +2 "$STUDENTS_FILE" | while IFS=, read -r id name email class; do
        # Check if student was previously marked present
        local status="off"
        if [ -f "$ATTENDANCE_DIR/$selected_date.csv" ]; then
            if grep -q "^$id," "$ATTENDANCE_DIR/$selected_date.csv"; then
                status="on"
            fi
        fi
        echo "$id \"$name ($class)\" $status" >> "$temp_checklist"
    done
    
    # Display checklist for attendance
    dialog --title "Attendance for $selected_date" \
           --checklist "Mark present students:" \
           $DIALOG_HEIGHT $DIALOG_WIDTH 15 \
           --file "$temp_checklist" \
           2> "$TEMP_FILE"
    
    # Check if user cancelled
    if [ $? -ne 0 ]; then
        rm -f "$temp_checklist" "$TEMP_FILE"
        return
    fi
    
    # Process selected students
    local present_students=$(cat "$TEMP_FILE" | tr -d '"')
    rm -f "$temp_checklist" "$TEMP_FILE"
    
    # Create or clear the attendance file for this date
    echo "id,status,timestamp" > "$ATTENDANCE_DIR/$selected_date.csv"
    
    # Mark all students as absent by default
    tail -n +2 "$STUDENTS_FILE" | while IFS=, read -r id name email class; do
        local status="absent"
        local current_time=$(date "+%H:%M:%S")
        
        # Check if this student is in the present list
        for present_id in $present_students; do
            if [ "$id" = "$present_id" ]; then
                status="present"
                break
            fi
        done
        
        # Record attendance
        echo "$id,$status,$current_time" >> "$ATTENDANCE_DIR/$selected_date.csv"
    done
    
    # Log action
    log_action "Attendance" "Recorded attendance for $selected_date"
    
    show_success "Attendance for $selected_date has been recorded"
}
