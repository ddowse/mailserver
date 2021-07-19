<?php
require ('config.php');

// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);
// Check connection
if ($conn->connect_error) {
	die("Connection failed: " . $conn->connect_error);
}


$sql = "REPLACE INTO `virtual_users` ( `id` , `domain_id` , `password` , `email` ) VALUES ('1', '1', 'password' , 'mailbox@${domain}')";

if ($conn->query($sql) === TRUE) {
	echo "New record created successfully";
} else {
	echo "Error: " . $sql . "\n" . $conn->error;
}

$conn->close();
?> 
