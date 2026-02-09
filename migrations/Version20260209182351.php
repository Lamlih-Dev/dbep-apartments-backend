<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

/**
 * Auto-generated Migration: Please modify to your needs!
 */
final class Version20260209182351 extends AbstractMigration
{
    public function getDescription(): string
    {
        return '';
    }

    public function up(Schema $schema): void
    {
        // this up() migration is auto-generated, please modify it to your needs
        $this->addSql('CREATE TEMPORARY TABLE __temp__apartment AS SELECT id, title, address, surface, rooms, price_per_night, description, image_url FROM apartment');
        $this->addSql('DROP TABLE apartment');
        $this->addSql('CREATE TABLE apartment (id BLOB NOT NULL, title VARCHAR(255) NOT NULL, address VARCHAR(255) DEFAULT NULL, surface INTEGER DEFAULT NULL, rooms INTEGER DEFAULT NULL, price_per_night INTEGER DEFAULT NULL, description CLOB DEFAULT NULL, image_url VARCHAR(255) DEFAULT NULL, PRIMARY KEY (id))');
        $this->addSql('INSERT INTO apartment (id, title, address, surface, rooms, price_per_night, description, image_url) SELECT id, title, address, surface, rooms, price_per_night, description, image_url FROM __temp__apartment');
        $this->addSql('DROP TABLE __temp__apartment');
    }

    public function down(Schema $schema): void
    {
        // this down() migration is auto-generated, please modify it to your needs
        $this->addSql('CREATE TEMPORARY TABLE __temp__apartment AS SELECT id, title, address, surface, rooms, price_per_night, description, image_url FROM apartment');
        $this->addSql('DROP TABLE apartment');
        $this->addSql('CREATE TABLE apartment (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, title VARCHAR(255) NOT NULL, address VARCHAR(255) DEFAULT NULL, surface INTEGER DEFAULT NULL, rooms INTEGER DEFAULT NULL, price_per_night INTEGER DEFAULT NULL, description CLOB DEFAULT NULL, image_url VARCHAR(255) DEFAULT NULL)');
        $this->addSql('INSERT INTO apartment (id, title, address, surface, rooms, price_per_night, description, image_url) SELECT id, title, address, surface, rooms, price_per_night, description, image_url FROM __temp__apartment');
        $this->addSql('DROP TABLE __temp__apartment');
    }
}
