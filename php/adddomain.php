<?php
require ('config.php');

// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);
// Check connection
if ($conn->connect_error) {
	die("Connection failed: " . $conn->connect_error);
}


$sql = "INSERT INTO virtual_domains (name) VALUES ('${domain}');";

if ($conn->query($sql) === TRUE) {
	echo "New record created successfully";
} else {
	echo "Error: " . $sql . "\n" . $conn->error;
}

$conn->close();
?> 
