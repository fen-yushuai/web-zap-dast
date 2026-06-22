<?php
session_start();
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $user = $_POST['username'] ?? '';
    $pass = $_POST['password'] ?? '';
    if ($user === 'admin' && $pass === 'admin') {
        $_SESSION['logged_in'] = true;
        header('Location: index.php');
        exit;
    }
    $error = 'Invalid credentials';
}
?>
<!DOCTYPE html>
<html><body>
<h1>Login</h1>
<?php if ($error): ?><p style="color:red"><?= $error ?></p><?php endif; ?>
<form method="post">
  <input name="username" placeholder="username"><br>
  <input name="password" type="password" placeholder="password"><br>
  <button type="submit">Login</button>
</form>
</body></html>
