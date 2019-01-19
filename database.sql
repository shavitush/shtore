/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8 */;
/*!50503 SET NAMES utf8mb4 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;

CREATE TABLE IF NOT EXISTS `store_items` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `type` enum('playermodel','chattitle','chatcolor') DEFAULT NULL,
  `enabled` TINYINT NOT NULL DEFAULT '1',
  `price` int(11) NOT NULL DEFAULT '100',
  `display` varchar(50) NOT NULL DEFAULT 'undefined',
  `description` varchar(50) DEFAULT NULL,
  `value` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `store_users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `auth` varchar(50) NOT NULL,
  `lastlogin` int(11) NOT NULL,
  `name` varchar(50) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
  `credits` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  INDEX `auth` (`auth`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `store_inventories` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `item_id` int(11) NOT NULL DEFAULT '0',
  `owner_id` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE INDEX `itempair` (`item_id`, `owner_id`),
  INDEX `item_id` (`item_id`),
  INDEX `owner_id` (`owner_id`),
  INDEX `server_id` (`server_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `store_equipped_items` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `owner_id` INT(11) NOT NULL,
  `slot` INT(11) NOT NULL,
  `item_id` INT(11) NOT NULL DEFAULT '-1',
  PRIMARY KEY (`id`),
  UNIQUE INDEX `owner_id_slot` (`owner_id`, `slot`),
  INDEX `owner_item_ids` (`owner_id`, `item_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `store_categories` (
  `server_id` TINYINT(4) NOT NULL,
  `categories` SET('playermodel','chattitle','chatcolor') NOT NULL,
  PRIMARY KEY (`server_Id`)
) ENGINE=InnoDB;

-- Dumping data for table shtore.store_items: ~0 rows (approximately)
/*!40000 ALTER TABLE `store_items` DISABLE KEYS */;
INSERT INTO `store_items` (`id`, `type`, `price`, `display`, `description`, `value`) VALUES
	(1, 'playermodel', 100, 'Captain America', 'A skin of Captain America. ', 'models/player/captain_america.mdl'),
	(2, 'playermodel', 150, 'Captain America but black', 'Black Captain America. This nigga smiling', 'models/player/captain_america_black.mdl'),
	(3, 'chattitle', 100, 'Rush B', 'go b fest men)))', '{green}[B] {team}{name}'),
	(4, 'chatcolor', 1000, 'Random', 'Random message color bro', '{rand}'),
	(5, 'chatcolor', 1500, 'uwu', 'uwu! pink and orchid', '{uwu}');
/*!40000 ALTER TABLE `store_items` ENABLE KEYS */;

/*!40101 SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '') */;
/*!40014 SET FOREIGN_KEY_CHECKS=IF(@OLD_FOREIGN_KEY_CHECKS IS NULL, 1, @OLD_FOREIGN_KEY_CHECKS) */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
