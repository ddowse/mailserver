<?php
require ('config.php');

// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);
// Check connection
if ($conn->connect_error) {
	die("Connection failed: " . $conn->connect_error);
}

$sql = "INSERT INTO virtual_aliases (domain_id, source, destination) VALUES ( (SELECT id FROM virtual_domains WHERE name='${domain}'), 'redirect@${domain}', 'support@mylinuxadmin.de');";

if ($conn->query($sql) === TRUE) {
	echo "New record created successfully";
} else {
	echo "Error: " . $sql . "\n" . $conn->error;
}

$conn->close();
?> 
