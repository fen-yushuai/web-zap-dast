<?php
session_start();
if (empty($_SESSION['logged_in'])) {
    header('Location: login.php');
    exit;
}
?>
<!DOCTYPE html>
<html><body>
<h1>Welcome</h1>
<p>You have logged in as 'admin'</p>
<a href="login.php">Logout</a>
</body></html>
